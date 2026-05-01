use jni::JNIEnv;
use jni::objects::{JClass, JString, JByteArray};
use jni::sys::{jint, jboolean, jlong};
use std::sync::{Arc, Mutex};
use std::collections::{HashMap, VecDeque};
use tokio::runtime::Runtime;
use bytes::Bytes;
use ostp_core::{NoiseRole, ProtocolConfig, ProtocolMachine, OstpEvent, ProtocolAction};
use std::net::SocketAddr;
use std::str::FromStr;
use serde_json;

struct OstpClient {
    machine: ProtocolMachine,
    outgoing: VecDeque<Vec<u8>>,
    incoming: VecDeque<Vec<u8>>,
}

impl OstpClient {
    fn new(
        session_id: u32,
        private_key: Vec<u8>,
        token: String,
        country: String,
        conn_type: String,
        hwid: String,
    ) -> Result<Self, Box<dyn std::error::Error>> {
        let config = ProtocolConfig {
            role: NoiseRole::Initiator,
            static_noise_key: private_key,
            remote_static_pubkey: None,
            session_id,
            handshake_payload: serde_json::json!({
                "token": token,
                "country": country,
                "conn_type": conn_type,
                "hwid": hwid
            }).to_string().into_bytes(),
            max_padding: 256,
        };
        
        let machine = ProtocolMachine::new(config)?;
        
        Ok(Self {
            machine,
            outgoing: VecDeque::new(),
            incoming: VecDeque::new(),
        })
    }
}

fn handle_action(client: &mut OstpClient, action: ProtocolAction) {
    match action {
        ProtocolAction::SendDatagram(frame) => {
            client.outgoing.push_back(frame.to_vec());
        }
        ProtocolAction::DeliverApp(stream_id, payload) => {
            let mut out = Vec::with_capacity(2 + payload.len());
            out.extend_from_slice(&stream_id.to_be_bytes());
            out.extend_from_slice(&payload);
            client.incoming.push_back(out);
        }
        ProtocolAction::HandshakePayload(_, response_opt) => {
            if let Some(resp) = response_opt {
                client.outgoing.push_back(resp.to_vec());
            }
        }
        ProtocolAction::Noop => {}
    }
}

thread_local! {
    static RUNTIME: Runtime = Runtime::new().unwrap();
    static CLIENTS: Arc<Mutex<HashMap<i64, Arc<Mutex<OstpClient>>>>> = Arc::new(Mutex::new(HashMap::new()));
    static NEXT_CLIENT_ID: Arc<Mutex<i64>> = Arc::new(Mutex::new(1));
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_createClient(
    mut env: JNIEnv,
    _class: JClass,
    server_addr: JString,
    session_id: jint,
    private_key: JByteArray,
    token: JString,
    country: JString,
    conn_type: JString,
    hwid: JString,
) -> jlong {
    let _server_addr_str: String = env.get_string(&server_addr).unwrap().into();
    let _server_addr = SocketAddr::from_str(&_server_addr_str).unwrap();
    let session_id = session_id as u32;
    let private_key = env.convert_byte_array(private_key).unwrap();
    let token: String = env.get_string(&token).unwrap().into();
    let country: String = env.get_string(&country).unwrap().into();
    let conn_type: String = env.get_string(&conn_type).unwrap().into();
    let hwid: String = env.get_string(&hwid).unwrap().into();
    
    let client_id = NEXT_CLIENT_ID.with(|id| {
        let mut id = id.lock().unwrap();
        let client_id = *id;
        *id += 1;
        client_id
    });
    
    match OstpClient::new(session_id, private_key, token, country, conn_type, hwid) {
        Ok(client) => {
            CLIENTS.with(|clients| {
                let mut clients = clients.lock().unwrap();
                clients.insert(client_id, Arc::new(Mutex::new(client)));
            });
            client_id
        }
        Err(_) => -1
    }
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_startClient(
    _env: JNIEnv,
    _class: JClass,
    client_id: jlong,
) -> jboolean {
    CLIENTS.with(|clients| {
        let clients = clients.lock().unwrap();
        if let Some(client) = clients.get(&client_id) {
            let mut client = client.lock().unwrap();
            match client.machine.on_event(OstpEvent::Start) {
                Ok(action) => {
                    handle_action(&mut client, action);
                    1
                }
                Err(_) => 0
            }
        } else {
            0
        }
    })
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_sendData(
    env: JNIEnv,
    _class: JClass,
    client_id: jlong,
    stream_id: jint,
    data: JByteArray,
) -> jboolean {
    let data = env.convert_byte_array(data).unwrap();
    
    CLIENTS.with(|clients| {
        let clients = clients.lock().unwrap();
        if let Some(client) = clients.get(&client_id) {
            let mut client = client.lock().unwrap();
            match client.machine.on_event(OstpEvent::Outbound(stream_id as u16, Bytes::from(data))) {
                Ok(action) => {
                    handle_action(&mut client, action);
                    1
                }
                Err(_) => 0
            }
        } else {
            0
        }
    })
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_receiveData(
    env: JNIEnv,
    _class: JClass,
    client_id: jlong,
    data: JByteArray,
) -> jboolean {
    let data = env.convert_byte_array(data).unwrap();
    
    CLIENTS.with(|clients| {
        let clients = clients.lock().unwrap();
        if let Some(client) = clients.get(&client_id) {
            let mut client = client.lock().unwrap();
            match client.machine.on_event(OstpEvent::Inbound(Bytes::from(data))) {
                Ok(action) => {
                    handle_action(&mut client, action);
                    1
                }
                Err(_) => 0
            }
        } else {
            0
        }
    })
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_getSendData<'a>(
    env: JNIEnv<'a>,
    _class: JClass<'a>,
    client_id: jlong,
) -> JByteArray<'a> {
    CLIENTS.with(|clients| {
        let clients = clients.lock().unwrap();
        if let Some(_client) = clients.get(&client_id) {
            let mut client = _client.lock().unwrap();
            if let Some(frame) = client.outgoing.pop_front() {
                env.byte_array_from_slice(&frame).unwrap()
            } else {
                env.byte_array_from_slice(&[]).unwrap()
            }
        } else {
            env.byte_array_from_slice(&[]).unwrap()
        }
    })
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_getAppData<'a>(
    env: JNIEnv<'a>,
    _class: JClass<'a>,
    client_id: jlong,
) -> JByteArray<'a> {
    CLIENTS.with(|clients| {
        let clients = clients.lock().unwrap();
        if let Some(client) = clients.get(&client_id) {
            let mut client = client.lock().unwrap();
            if let Some(msg) = client.incoming.pop_front() {
                env.byte_array_from_slice(&msg).unwrap()
            } else {
                env.byte_array_from_slice(&[]).unwrap()
            }
        } else {
            env.byte_array_from_slice(&[]).unwrap()
        }
    })
}

#[no_mangle]
pub extern "C" fn Java_com_ospab_byteaway_service_OstpJni_closeClient(
    _env: JNIEnv,
    _class: JClass,
    client_id: jlong,
) {
    CLIENTS.with(|clients| {
        let mut clients = clients.lock().unwrap();
        clients.remove(&client_id);
    });
}
