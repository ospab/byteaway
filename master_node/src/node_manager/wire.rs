//! Shared binary wire protocol for node-to-master communication.
//!
//! Frame format: `[1 byte CMD][16 bytes SessionID (UUID)][N bytes Payload]`
//!
//! Used by all tunnel implementations (WebSocket, QUIC, TUIC, HY2).

use uuid::Uuid;

pub const CMD_CONNECT: u8 = 0x01;
pub const CMD_DATA: u8 = 0x02;
pub const CMD_CLOSE: u8 = 0x03;

/// Minimum frame size: 1 (cmd) + 16 (uuid) = 17 bytes.
pub const MIN_FRAME_SIZE: usize = 17;

/// Encode a wire frame from command, session ID, and payload.
pub fn encode(cmd: u8, session_id: Uuid, payload: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(1 + 16 + payload.len());
    frame.push(cmd);
    frame.extend_from_slice(session_id.as_bytes());
    frame.extend_from_slice(payload);
    frame
}

/// Decode a wire frame into (command, session_id, payload).
/// Returns `None` if the frame is too short.
pub fn decode(data: &[u8]) -> Option<(u8, Uuid, &[u8])> {
    if data.len() < MIN_FRAME_SIZE {
        return None;
    }
    let cmd = data[0];
    let sid = Uuid::from_bytes(data[1..17].try_into().ok()?);
    Some((cmd, sid, &data[17..]))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip() {
        let sid = Uuid::new_v4();
        let payload = b"hello";
        let frame = encode(CMD_DATA, sid, payload);
        let (cmd, decoded_sid, decoded_payload) = decode(&frame).unwrap();
        assert_eq!(cmd, CMD_DATA);
        assert_eq!(decoded_sid, sid);
        assert_eq!(decoded_payload, payload);
    }

    #[test]
    fn short_frame() {
        assert!(decode(&[0x01; 10]).is_none());
    }
}
