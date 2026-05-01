use bytes::Bytes;
use thiserror::Error;

use crate::crypto::{NoiseRole, NoiseSession, SessionCipher};
use crate::framing::{AdaptivePadder, FrameHeader, FrameKind, FramedPacket, PaddingStrategy};

#[derive(Debug, Error)]
pub enum ProtocolError {
    #[error("state error: {0}")]
    State(String),
    #[error("crypto error: {0}")]
    Crypto(String),
    #[error("framing error: {0}")]
    Framing(String),
}

#[derive(Debug, Clone)]
pub struct ProtocolConfig {
    pub role: NoiseRole,
    pub static_noise_key: Vec<u8>,
    pub remote_static_pubkey: Option<Vec<u8>>,
    pub session_id: u32,
    pub handshake_payload: Vec<u8>,
    pub max_padding: usize,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum OstpState {
    Init,
    Handshaking,
    Established,
    Closing,
    Closed,
}

pub enum OstpEvent {
    Start,
    Inbound(Bytes),
    Outbound(u16, Bytes), // stream_id, payload
    Close,
}

pub enum ProtocolAction {
    SendDatagram(Bytes), // Fully formed datagram to send globally
    DeliverApp(u16, Bytes), // stream_id, payload
    HandshakePayload(Bytes, Option<Bytes>), // Passed from client's handshake, Optional response to send
    Noop,
}

pub struct ProtocolMachine {
    role: NoiseRole,
    state: OstpState,
    noise: NoiseSession,
    cipher: Option<SessionCipher>,
    send_nonce: u64,
    _recv_nonce: u64,
    session_id: u32,
    handshake_payload: Vec<u8>,
    padder: AdaptivePadder,
}

impl ProtocolMachine {
    pub fn new(config: ProtocolConfig) -> Result<Self, ProtocolError> {
        let noise = NoiseSession::new(
            config.role,
            &config.static_noise_key,
            config.remote_static_pubkey.as_deref(),
        )?;

        Ok(Self {
            role: config.role,
            state: OstpState::Init,
            noise,
            cipher: None,
            send_nonce: 0,
            _recv_nonce: 0,
            session_id: config.session_id,
            handshake_payload: config.handshake_payload,
            padder: AdaptivePadder::new(1200, config.max_padding, PaddingStrategy::Adaptive),
        })
    }

    pub fn state(&self) -> OstpState {
        self.state
    }

    pub fn on_event(&mut self, event: OstpEvent) -> Result<ProtocolAction, ProtocolError> {
        match (self.state, event) {
            (OstpState::Init, OstpEvent::Start) => {
                match self.role {
                    NoiseRole::Initiator => {
                        self.state = OstpState::Handshaking;
                        let mut out = vec![0_u8; 1024];
                        let n = self.noise.write_handshake(&self.handshake_payload, &mut out)?;
                        out.truncate(n);
                        self.wrap_datagram_handshake(&out)
                            .map(ProtocolAction::SendDatagram)
                    }
                    NoiseRole::Responder => {
                        self.state = OstpState::Handshaking;
                        Ok(ProtocolAction::Noop)
                    }
                }
            }
            (OstpState::Init, OstpEvent::Inbound(raw)) => {
                self.state = OstpState::Handshaking;
                self.handle_inbound(raw)
            }
            (OstpState::Handshaking, OstpEvent::Inbound(raw)) => {
                self.handle_inbound(raw)
            }
            (OstpState::Handshaking, OstpEvent::Start) => Ok(ProtocolAction::Noop),
            (OstpState::Established, OstpEvent::Outbound(stream_id, app_data)) => {
                self.build_data_datagram(stream_id, FrameKind::Data, app_data)
                    .map(ProtocolAction::SendDatagram)
            }
            (OstpState::Established, OstpEvent::Inbound(raw)) => {
                self.handle_inbound(raw)
            }
            (OstpState::Established, OstpEvent::Close) => {
                self.state = OstpState::Closing;
                self.build_data_datagram(0, FrameKind::Close, Bytes::new())
                    .map(ProtocolAction::SendDatagram)
            }
            (OstpState::Closing, OstpEvent::Inbound(_)) => {
                self.state = OstpState::Closed;
                Ok(ProtocolAction::Noop)
            }
            (OstpState::Closed, _) => Ok(ProtocolAction::Noop),
            (_, OstpEvent::Close) => {
                self.state = OstpState::Closed;
                Ok(ProtocolAction::Noop)
            }
            _ => Ok(ProtocolAction::Noop),
        }
    }

    fn handle_inbound(&mut self, raw: Bytes) -> Result<ProtocolAction, ProtocolError> {
        if raw.len() < 4 {
            return Err(ProtocolError::Framing("datagram too short".to_string()));
        }

        let session_id = u32::from_be_bytes([raw[0], raw[1], raw[2], raw[3]]);
        if session_id != self.session_id {
            return Err(ProtocolError::State("session id mismatch".to_string()));
        }

        if self.state == OstpState::Handshaking {
            let mut read_out = vec![0_u8; 1024];
            let n = self.noise.read_handshake(&raw[4..], &mut read_out)?;

            let response = match self.role {
                NoiseRole::Responder => {
                    let mut write_out = vec![0_u8; 1024];
                    let out_n = self.noise.write_handshake(&self.handshake_payload, &mut write_out)?;
                    write_out.truncate(out_n);
                    Some(self.wrap_datagram_handshake(&write_out)?)
                }
                NoiseRole::Initiator => None,
            };

            let mut key = [0_u8; 32];
            self.noise.handshake_hash(&mut key)?;
            self.cipher = Some(SessionCipher::new(&key));
            self.state = OstpState::Established;

            let extracted_payload = read_out[..n].to_vec();

            return Ok(ProtocolAction::HandshakePayload(Bytes::from(extracted_payload), response));
        } else if self.state == OstpState::Established {
            if raw.len() < 4 + 8 {
                return Err(ProtocolError::Framing("data datagram too short".to_string()));
            }
            let nonce = u64::from_be_bytes(raw[4..12].try_into().unwrap());
            let ciphertext = &raw[12..];

            let cipher = self.cipher.as_ref().ok_or_else(|| {
                ProtocolError::State("missing session cipher".to_string())
            })?;

            let session_id_bytes = self.session_id.to_be_bytes();
            let plaintext = cipher.decrypt(nonce, ciphertext, &session_id_bytes)?;
            
            let packet = FramedPacket::decode_zero_copy(Bytes::from(plaintext))?;
            match packet.header.kind {
                FrameKind::Data => {
                    Ok(ProtocolAction::DeliverApp(packet.header.stream_id, packet.payload))
                }
                FrameKind::Close => {
                    self.state = OstpState::Closed;
                    Ok(ProtocolAction::Noop)
                }
                FrameKind::KeepAlive => {
                    Ok(ProtocolAction::Noop)
                }
                _ => Ok(ProtocolAction::Noop),
            }
        } else {
            Ok(ProtocolAction::Noop)
        }
    }

    fn wrap_datagram_handshake(&self, noise_payload: &[u8]) -> Result<Bytes, ProtocolError> {
        let mut out = Vec::with_capacity(4 + noise_payload.len());
        out.extend_from_slice(&self.session_id.to_be_bytes());
        out.extend_from_slice(noise_payload);
        Ok(Bytes::from(out))
    }

    fn build_data_datagram(&mut self, stream_id: u16, kind: FrameKind, payload: Bytes) -> Result<Bytes, ProtocolError> {
        let padding = self.padder.build_padding(payload.len());
        let header = FrameHeader {
            version: 1,
            kind,
            flags: 0,
            stream_id,
            payload_len: payload.len() as u32,
            pad_len: padding.len() as u16,
        };

        let packet = FramedPacket {
            header,
            payload,
            padding: Bytes::from(padding),
        };

        let plaintext = packet.encode();
        
        let cipher = self.cipher.as_ref().ok_or_else(|| {
            ProtocolError::State("missing session cipher".to_string())
        })?;

        let nonce = self.send_nonce;
        self.send_nonce = self.send_nonce.saturating_add(1);

        let session_id_bytes = self.session_id.to_be_bytes();
        let ciphertext = cipher.encrypt(nonce, plaintext.as_ref(), &session_id_bytes)?;

        let mut out = Vec::with_capacity(4 + 8 + ciphertext.len());
        out.extend_from_slice(&session_id_bytes);
        out.extend_from_slice(&nonce.to_be_bytes());
        out.extend_from_slice(&ciphertext);

        Ok(Bytes::from(out))
    }
}
