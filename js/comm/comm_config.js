const WEBRTC_CONFIGURATION = {
    "iceServers": [
        {"urls": ["stun:stun.l.google.com:19302"]},
        {"urls": ["stun:stun.services.mozilla.com:3478"]},
        {"urls": ["stun:stun2.l.google.com:19302"]},
        {"urls": ["stun:stun3.l.google.com:19302"]},
        {"urls": ["stun:stun4.l.google.com:19302"]}
    ],
    "iceTransportPolicy": "all",
    "iceCandidatePoolSize": "0"
};

const SIGNALLING_SERVER_URL = "http://localhost:3000";  // TODO: add the server URL here