use anyhow::Result;
use bytes::Bytes;
use ostp_core::framing::{FrameKind, FramedPacket};
use ostp_core::{OstpEvent, ProtocolAction, ProtocolConfig, ProtocolMachine};
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{Arc, RwLock};

pub enum DispatchOutcome {
    Unauthorized,
    Accepted {
        response: Option<Bytes>,
        app_payload: Option<(u32, u16, Bytes)>, // session_id, stream_id, payload
        peer_addr: SocketAddr,
    },
}

pub struct PeerState {
    pub machine: ProtocolMachine,
    pub last_addr: SocketAddr,
}

pub struct Dispatcher {
    peer_machines: HashMap<u32, PeerState>,
    machine_config: ProtocolConfig,
    access_keys: Arc<RwLock<HashMap<String, ()>>>,
}

impl Dispatcher {
    pub fn new(machine_config: ProtocolConfig, access_keys: Arc<RwLock<HashMap<String, ()>>>) -> Self {
        Self {
            peer_machines: HashMap::new(),
            machine_config,
            access_keys,
        }
    }

    pub fn on_datagram(&mut self, peer: SocketAddr, packet: Bytes) -> Result<DispatchOutcome> {
        if packet.len() < 4 {
            return Ok(DispatchOutcome::Unauthorized);
        }
        let session_id = u32::from_be_bytes([packet[0], packet[1], packet[2], packet[3]]);

        if !self.peer_machines.contains_key(&session_id) {
            let mut cfg = self.machine_config.clone();
            cfg.session_id = session_id;
            // The server does not send a handshake payload, so it's empty
            cfg.handshake_payload = vec![];
            
            let mut machine = ProtocolMachine::new(cfg)?;
            let action = machine.on_event(OstpEvent::Inbound(packet.clone()))?;

            if let ProtocolAction::HandshakePayload(payload, response_opt) = action {
                if let Ok(key) = std::str::from_utf8(&payload) {
                    let authorized = self.access_keys.read().unwrap().contains_key(key);
                    if authorized {
                        self.peer_machines.insert(session_id, PeerState {
                            machine,
                            last_addr: peer,
                        });
                        return Ok(DispatchOutcome::Accepted {
                            response: response_opt,
                            app_payload: None,
                            peer_addr: peer,
                        });
                    }
                }
            }
            return Ok(DispatchOutcome::Unauthorized);
        }

        let mut peer_state = self.peer_machines.remove(&session_id).unwrap();
        // Update peer addr for roaming
        peer_state.last_addr = peer;

        let action = peer_state.machine.on_event(OstpEvent::Inbound(packet));
        let outcome = match action {
            Ok(ProtocolAction::SendDatagram(frame)) => Ok(DispatchOutcome::Accepted {
                response: Some(frame),
                app_payload: None,
                peer_addr: peer,
            }),
            Ok(ProtocolAction::DeliverApp(stream_id, payload)) => Ok(DispatchOutcome::Accepted {
                response: None,
                app_payload: Some((session_id, stream_id, payload)),
                peer_addr: peer,
            }),
            Ok(_) => Ok(DispatchOutcome::Accepted {
                response: None,
                app_payload: None,
                peer_addr: peer,
            }),
            Err(_) => Ok(DispatchOutcome::Unauthorized),
        };

        if !matches!(outcome, Ok(DispatchOutcome::Unauthorized)) {
            self.peer_machines.insert(session_id, peer_state);
        }
        
        outcome
    }

    pub fn outbound_to_session(&mut self, session_id: u32, stream_id: u16, payload: Bytes) -> Result<Option<(Bytes, SocketAddr)>> {
        let peer_state = if let Some(existing) = self.peer_machines.get_mut(&session_id) {
            existing
        } else {
            return Ok(None);
        };

        let addr = peer_state.last_addr;
        match peer_state.machine.on_event(OstpEvent::Outbound(stream_id, payload))? {
            ProtocolAction::SendDatagram(frame) => Ok(Some((frame, addr))),
            _ => Ok(None),
        }
    }

    pub fn drop_session(&mut self, session_id: u32) {
        self.peer_machines.remove(&session_id);
    }
}
