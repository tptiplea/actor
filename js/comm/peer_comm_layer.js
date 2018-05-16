//* CONSTANTS **////
// Provides: PCL_CONSTS
// Requires: make_random_id
const PCL_CONSTS = {
    MY_UNIQUE_ID : make_random_id(20),
    SERVER_TO_PEER_KIND : 'SERVER_TO_PEER',
    PEER_TO_SERVER_KIND : 'PEER_TO_SERVER',
    PEER_TO_PEER_KIND : 'PEER_TO_PEER',
    REGISTER_UNIXSOCKET_OP : 'REGISTER_UNIXSOCKET',
    UNREGISTER_UNIXSOCKET_OP : 'UNREGISTER_UNIXSOCKET',
    SERVER_PEER_TO_PEER_OP : 'PEER_TO_PEER_OP_SERVER',
    MSG_PEER_TO_PEER_OP : 'MSG_PEER_TO_PEER_OP',
    CONNECTION_OP : 'CONNECTION_OP',
    ACK_OP : 'ACK_OPERATION',
    OK_STATUS : 'SUCCESS',
    FAIL_STATUS : 'FAIL',
    CONNECTED_TO_SERVER_PROMISE_NAME : "connected_to_server_promise",
    RTC_ICECANDIDATE : "RTC_ICECANDIDATE",
    RTC_DESCRIPTION : "RTC_DESCRIPTION"
};

//****************///


////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
// Provides: PCL_VARS
var PCL_VARS = {
    SIGNALLING_SERVER_URL : undefined,
    IOSOCKET : undefined,
    _IS_PCL_START_REQUESTED : false,
    TOTAL_MESSAGES_SENT : 0,
    UNIXSOCKET_ID_TO_WEBRTC_DICT : {}, // keep track of unixsocket ids bound on this server
    PROMISES_DICT : {}, // keep track of promises
    RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO : {} // a callback called with two arguments, (from, msg) on each message rcvd for that unixsocket
};
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************

// Starts the PCL layer, must be called before any other function.
// Returns a promise which is resolved with the unique id of this program when connected to signalling server.
// Provides: start_pcl_layer
// Requires: PCL_VARS, PCL_CONSTS, create_promise, get_existing_promise
function start_pcl_layer(signalling_server_url) {
    if (!PCL_VARS._IS_PCL_START_REQUESTED) {
        // Only if we didn't request start already.
        PCL_VARS._IS_PCL_START_REQUESTED = true;

        PCL_VARS.SIGNALLING_SERVER_URL = signalling_server_url;
        PCL_VARS.IOSOCKET = io(signalling_server_url);

        // Connect to server.
        PCL_VARS.IOSOCKET.on('server_to_peer', process_msg_from_server);

        // The semaphore that tells us whether we're connected to the server.
        create_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME, 5 * 60 * 1000); // Timeout if we don't connect to server in that time.
    }

    return get_existing_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
        console.log('CONNECTED TO IO SERVER, got id:', PCL_CONSTS.MY_UNIQUE_ID);
        return PCL_CONSTS.MY_UNIQUE_ID;
    });
}



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET send stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
// Send a msg to server, return a promise after that is done.
// Provides: send_msg_to_server
// Requires: PCL_VARS, PCL_CONSTS, get_existing_promise
function send_msg_to_server(msg) {
    return get_existing_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
        PCL_VARS.IOSOCKET.emit('peer_to_server', msg);
    });
}
/** ------------------------------------------------ IOSOCKET send stuff} ------------------------------- */



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET receive stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
// Provides: process_msg_from_server
// Requires: PCL_VARS, PCL_CONSTS, promise_name_for_register_unixsocket_id, promise_name_for_unregister_unixsocket_id, resolve_promise, reject_promise, promise_name_from_msg_id_ack, process_msg_from_unixsocket
function process_msg_from_server(msg) {
    if (msg.kind === PCL_CONSTS.SERVER_TO_PEER_KIND) {
        // A message from the server.

        if (msg.operation === PCL_CONSTS.REGISTER_UNIXSOCKET_OP || msg.operation === PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP) {
            // The result of (un)register operation.
            var result = msg.result;
            var unixsocket_id = msg.unixsocket_id;
            var promise_name =
                msg.operation === PCL_CONSTS.REGISTER_UNIXSOCKET_OP ? promise_name_for_register_unixsocket_id(unixsocket_id)
                    : promise_name_for_unregister_unixsocket_id(unixsocket_id);
            if (result === PCL_CONSTS.OK_STATUS) {
                resolve_promise(promise_name, PCL_CONSTS.OK_STATUS);
            }
            else {
                reject_promise(promise_name, msg.error_msg);
            }

        } else if (msg.operation === PCL_CONSTS.CONNECTION_OP) {
            // Successfully connected to server.
            resolve_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME);
        } else if (msg.operation === PCL_CONSTS.SERVER_PEER_TO_PEER_OP) {
            if (msg.result !== PCL_CONSTS.OK_STATUS) {
                // Server failed to send a message to other peer, probably waitlisted.
                console.log(msg.error_msg);
            }
        } else {
            throw "Unknown SERVER_TO_PEER operation " + msg.operation;
        }

    } else if (msg.kind === PCL_CONSTS.PEER_TO_PEER_KIND) {
        // A message from another peer, redirected by the server.
        if (msg.operation === PCL_CONSTS.ACK_OP) {
            // An ack for a message from here, update the promise accordingly!.
            var msg_id = msg.msg_id;
            try {
                var promise_name = promise_name_from_msg_id_ack(msg_id);
                if (msg.result === PCL_CONSTS.OK_STATUS) {
                    resolve_promise(promise_name, PCL_CONSTS.OK_STATUS);
                } else {
                    reject_promise(promise_name, msg.result);
                }
            } catch (err) {
                console.log('Ack for a non existing message probably:', err);
            }

        } else if (msg.operation === PCL_CONSTS.MSG_PEER_TO_PEER_OP) {
            var from_unixsocket_id = msg.from_unixsocket_id;
            var to_unixsocket_id = msg.to_unixsocket_id;
            var payload = msg.payload;
            var msg_id = msg.msg_id;

            process_msg_from_unixsocket(from_unixsocket_id, to_unixsocket_id, payload, msg_id);
        }

    } else {
        throw "Unknown message kind " + msg;
    }
}

/** ------------------------------------------------  IOSOCKET receive stuff} ------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ REGISTER/UNREGISTER UNIXSOCKETS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
// Register a unixsocket_id, with this peer and the signalling server.
// Returns a promise resolved when the address is bound correctly.
// Provides: register_unixsocket_id
// Requires: PCL_VARS, PCL_CONSTS, promise_name_for_register_unixsocket_id, send_msg_to_server, log_error, create_promise
function register_unixsocket_id(unixsocket_id, on_msg_callback, on_connection_to_callback) {
    if (unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT) {
        return Promise.reject("Unixsocket with id " + unixsocket_id + " already bound");
    }
    PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[unixsocket_id] = {}; // all the sockets we are connected to.
    PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[unixsocket_id] = {
        'on_msg_callback' : on_msg_callback,
        'on_connection_to_callback' : on_connection_to_callback
    };

    var promise_name = promise_name_for_register_unixsocket_id(unixsocket_id);
    var promise = create_promise(promise_name, 120 * 1000);
    return send_msg_to_server({
        'kind': PCL_CONSTS.PEER_TO_SERVER_KIND,
        'operation': PCL_CONSTS.REGISTER_UNIXSOCKET_OP,
        'unixsocket_id': unixsocket_id
    }).then(function (_) {
        return promise;
    }).catch(function (reason) {
        delete PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[unixsocket_id];
        delete PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[unixsocket_id];
        log_error(reason);
        throw reason; // Pass the error forward
    });
}

// Provides: unregister_unixsocket_id
// Requires: PCL_VARS, PCL_CONSTS, promise_name_for_unregister_unixsocket_id, send_msg_to_server, log_error, create_promise
function unregister_unixsocket_id(unixsocket_id) {
    if (!(unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT)) {
        return Promise.reject("Unixsocket with id " + unixsocket_id + " not bound!");
    }
    delete PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[unixsocket_id];
    delete PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[unixsocket_id];

    var promise_name = promise_name_for_unregister_unixsocket_id(unixsocket_id);
    var promise = create_promise(promise_name, 120 * 1000);
    return send_msg_to_server({
        'kind': PCL_CONSTS.PEER_TO_SERVER_KIND,
        'operation': PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP,
        'unixsocket_id': unixsocket_id
    }).then(function (_) {
        return promise;
    });
}


/** --------------------------- REGISTER/UNREGISTER UNIXSOCKETS --------------------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER_TO_PEER_MSG (SIGNALLING) ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER_TO_PEER_MSG (SIGNALLING) ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER_TO_PEER_MSG (SIGNALLING) ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// id, from this socket, send it to
// Sends an ack to the other unixsocket_id over the signalling channel
// Provides: send_ack_to_unixsocket
// Requires: PCL_VARS, PCL_CONSTS, send_msg_to_server
function send_ack_to_unixsocket(msg_id, from_unixsocket_id, to_unixsocket_id) {
    return send_msg_to_server({
       'kind': PCL_CONSTS.PEER_TO_PEER_KIND,
       'operation': PCL_CONSTS.ACK_OP,
        'result': PCL_CONSTS.OK_STATUS,
        'msg_id': msg_id,
        'to_unixsocket_id': to_unixsocket_id,
        'from_unixsocket_id': from_unixsocket_id
    });
}

// Processes a message received over the signalling channel.
// Provides: process_msg_from_unixsocket
// Requires: PCL_VARS, PCL_CONSTS, send_ack_to_unixsocket, set_up_rtcpeerconnection, send_msg_to_unixsocket, log_error
function process_msg_from_unixsocket(from_unixsocket_id, to_unixsocket_id, payload, msg_id) {
    if (!(to_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT)) {
        log_error('ERROR!!!: Got a message for an unregistered unixsocket_id' + 'to_unixsocket_id' + '. Dropping it.');
    }
    // Pretty much always ack the message first.
    var other_unixsocket_id = from_unixsocket_id; // to other
    var me_unixsocket_id = to_unixsocket_id; // from me (reverse)
    send_ack_to_unixsocket(msg_id, me_unixsocket_id, other_unixsocket_id);
    // ---------

    if ((typeof payload !== 'object')
        || (!('webrtc_type' in payload))
        || (payload.webrtc_type !== PCL_CONSTS.RTC_ICECANDIDATE && payload.webrtc_type !== PCL_CONSTS.RTC_DESCRIPTION)) {
        console.log('Unexpected kind of message:', payload);
        console.log('Dropping it!');
        return;
    }

    if (!(other_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[me_unixsocket_id])) {
        // First kind of message, start setting it up.
        set_up_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id, false).catch(log_error);
    }

    var pc = PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[me_unixsocket_id][other_unixsocket_id].pc;
    if (payload.webrtc_type === PCL_CONSTS.RTC_ICECANDIDATE) {
        // An ice candidate.
        pc.addIceCandidate(new RTCIceCandidate(payload.icecandidate)).catch(log_error);
    } else if (payload.webrtc_type === PCL_CONSTS.RTC_DESCRIPTION) {
        var desc = payload.description;
        if (desc.type === 'offer') {
            // we got an offer, set it then set up the answer.
            pc.setRemoteDescription(desc).then(function () {
                return pc.createAnswer();
            }).then(function (answer) {
                // Set the answer as the local description
                return pc.setLocalDescription(answer);
            }).then(function() {
                // send it over.
                send_msg_to_unixsocket(me_unixsocket_id, other_unixsocket_id, {
                    'webrtc_type' : PCL_CONSTS.RTC_DESCRIPTION,
                    'description' : pc.localDescription
                });
            });

        } else {
            // we got an answer, set it as the remote description.
            pc.setRemoteDescription(desc).catch(log_error);
        }
    }
}

// Send a message over the signalling channel.
// Provides: send_msg_to_unixsocket
// Requires: PCL_VARS, PCL_CONSTS, send_msg_to_server, create_promise, update_msg_count_and_get_unique_id, promise_name_from_msg_id_ack
function send_msg_to_unixsocket(from_unixsocket_id, to_unixsocket_id, payload) {
    var msg_id = update_msg_count_and_get_unique_id();
    send_msg_to_server({
        'kind': PCL_CONSTS.PEER_TO_PEER_KIND,
        'operation': PCL_CONSTS.MSG_PEER_TO_PEER_OP,
        'from_unixsocket_id': from_unixsocket_id,
        'to_unixsocket_id': to_unixsocket_id,
        'payload': payload,
        'msg_id': msg_id
    });
    // create the promise, but don't return it, it can be obtained from the msg id if required.
    create_promise(promise_name_from_msg_id_ack(msg_id));
    return msg_id;
}


/** ------------------------------------------------  PEER_TO_PEER_MSG ------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONNECT_WEBRTC ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONNECT_WEBRTC ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONNECT_WEBRTC ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONNECT_WEBRTC ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// Tear down an RTCPeerConnection, if one is available.
function tear_down_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id) {
    if (me_unixsocket_id in PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO) {
        PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[me_unixsocket_id].on_connection_to_callback(me_unixsocket_id, other_unixsocket_id, false);
    }
    if (!(me_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT)
        || !(other_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[me_unixsocket_id])) {
        // no connection, no need for tear down.
        return;
    }
    delete PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[me_unixsocket_id][other_unixsocket_id];
}

// Set up an RTCPeerConnection and a DataChannel between these two sockets.
// Returns a promise resolved when the data channel is open.
// Provides: set_up_rtc_peerconnection
// Requires: PCL_VARS, PCL_CONSTS, send_msg_to_unixsocket, rtc_process_received_message, add_timeout_to_promise, log_warning
function set_up_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id, am_caller) {
    var resolver = null;
    var rejector = null;
    var open_channel_promise = add_timeout_to_promise(
        new Promise(function (resolve, reject) {resolver = resolve; rejector = reject;}),
        60 * 1000,
        'Setting up the RTCPeerConnecton timed-out');

    var pc = new RTCPeerConnection(WEBRTC_CONFIGURATION);
    PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[me_unixsocket_id][other_unixsocket_id] = {
        'pc' : pc,
        'channel_promise' : open_channel_promise
    }; // VERY IMPORTANT! Store in the global dict

    pc.onicecandidate = function (event) {
        if (event.candidate) {
            // A new ICE candidate, send it over to other peer.
            send_msg_to_unixsocket(me_unixsocket_id, other_unixsocket_id, {
                'webrtc_type' : PCL_CONSTS.RTC_ICECANDIDATE,
                'icecandidate' : event.candidate
            });
        }
    };

    // This will be called on one of them, to make an offer.
    pc.onnegotiationneeded = function (_) {
        pc.createOffer().then(function (offer) {
            return pc.setLocalDescription(offer); // first set the local description
        }).then(function () {
            // now set, send the description over to the other peer.
            send_msg_to_unixsocket(me_unixsocket_id, other_unixsocket_id, {
                'webrtc_type' : PCL_CONSTS.RTC_DESCRIPTION,
                'description' : pc.localDescription
            })

        }).catch(function (reason) {
            log_error(reason);
            rejector(reason); // Fail the other promise
        });
    };

    function add_listeners_on_channel(channel) {
        if (!channel.reliable) {
            log_warning('Channel between ' + me_unixsocket_id + ' and ' + other_unixsocket_id + ' is not reliable!');
        }
        channel.onopen = function (_) {
            resolver(channel); // resolve the promise when we get the channel open.
        };

        channel.onclose = function (_) {
            log_warning('Datachannel between' + other_unixsocket_id + 'and' + me_unixsocket_id + 'has closed down');
            tear_down_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id);
        };

        channel.onmessage = function (event) {
            rtc_process_received_message(other_unixsocket_id, me_unixsocket_id, event.data);
        }
    }

    pc.onclose = function (_) {
        console.log('RTCPeerConnection between', other_unixsocket_id, 'and', me_unixsocket_id, 'has closed down');
    };

    if (am_caller) {
        add_listeners_on_channel(pc.createDataChannel(me_unixsocket_id + other_unixsocket_id));
    } else {
        pc.ondatachannel = function (event) {
            add_listeners_on_channel(event.channel);
        };
    }

    return open_channel_promise.then(function (channel) {
        // Notify the listener of a new connection.
        PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[me_unixsocket_id].on_connection_to_callback(me_unixsocket_id, other_unixsocket_id, true);
        return channel;
    }).catch(function (reason) {
        // Make sure to teardown the connection here.
        tear_down_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id);
        throw reason; // But pass the error forward.
    });
}

// Connect to this socket.
// Returns a promise that resolves to the from_unixsocket_id that is connected (listening) to this other remote peer.
// This will be a new socket.
// Provides: connect_to_unixsocket
// Requires: PCL_VARS, PCL_CONSTS, get_unused_unixsocket_id, register_unixsocket_id, set_up_rtcpeerconnection
function connect_to_unixsocket(to_unixsocket_id, on_msg_callback, on_connection_to_callback) {
    var from_unixsocket_id = get_unused_unixsocket_id();
    // This will contain the result of the connection, either the from_unixsocket_id connected to this
    // Or a failure.

    // Register the listening unixsocket.
    return register_unixsocket_id(from_unixsocket_id, on_msg_callback, on_connection_to_callback).then(function (_) {
        // Set up the rtcpeerconnection.
        return set_up_rtcpeerconnection(from_unixsocket_id, to_unixsocket_id, true);

    }).then(function () { // when that is successful as well, return the socket we're listening on.
        return from_unixsocket_id;
    });
}

/** ------------------------------------------------  CONNECT_WEBRTC ------------------------------- */
/** ------------------------------------------------  CONNECT_WEBRTC ------------------------------- */
/** ------------------------------------------------  CONNECT_WEBRTC ------------------------------- */



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ WEBRTC_SEND_RECV ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ WEBRTC_SEND_RECV ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ WEBRTC_SEND_RECV ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ WEBRTC_SEND_RECV ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// Process a message received over the RTC channel
// Provides: rtc_process_received_message
// Requires: PCL_VARS, PCL_CONSTS
function rtc_process_received_message(from_unixsocket_id, to_unixsocket_id, msg) {
    if (to_unixsocket_id in PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO) {
        // Call the callback.
        (PCL_VARS.RTC_UNIXSOCKET_ONMSGCALLBACK_AND_ONCONNECTIONTO[to_unixsocket_id].on_msg_callback)(from_unixsocket_id, to_unixsocket_id, msg);
    } else {
        // Drop it.
    }
}

// Send a message over the rtc channel.
// Returns a promise that resolves when the channel is open and the message was sent.
// Provides: rtc_send_msg
// Requires: PCL_VARS, PCL_CONSTS
function rtc_send_msg(from_unixsocket_id, to_unixsocket_id, msg) {
    if (!(to_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[from_unixsocket_id])) {
        var error_msg = "ERROR: " + "The local socket -" + from_unixsocket_id +
            "- is not connected to remote socket-" + to_unixsocket_id + "!";
        log_error(error_msg);
        return Promise.reject(error_msg);
    }

    var open_channel_promise = PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[from_unixsocket_id][to_unixsocket_id].channel_promise;

    return open_channel_promise.then(function (channel) {
        channel.send(msg);
    });
}

/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */
/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */
/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ jsapi WITH CALLBACKS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ jsapi WITH CALLBACKS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ jsapi WITH CALLBACKS ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// Function that starts the communication layer and calls the callback when connected to the signalling server.
// The callback is passed the Unique ID of this peer.
// Needs the signalling server URL as the first argument.
// Provides: pcl_jsapi_start_comm_layer
// Requires: start_pcl_layer
function pcl_jsapi_start_comm_layer(signalling_server_url, on_success_callback, on_failure_callback) {
    start_pcl_layer(signalling_server_url).then(function (unique_id) {
        on_success_callback(unique_id);
    }).catch(function (reason) {
        on_failure_callback(reason);
    });
}

// Function that binds an address (must be unique),
// calling the on_success_callback on success, or the failure_callback with the reason on fail.
// Provides: pcl_jsapi_bind_address
// Requires: register_unixsocket_id
function pcl_jsapi_bind_address(unixsocket_id, on_msg_callback, on_connection_to_callback, on_success_callback, on_failure_callback) {
    register_unixsocket_id(unixsocket_id, on_msg_callback, on_connection_to_callback).then(function (_) {
        on_success_callback();
    }).catch(function (reason) {
        on_failure_callback(reason);
    });
}

// Function that deallocates an address (must be already registered),
// calling the on_success_callback on success, or the failure_callback with the reason on fail.
// Provides: pcl_jsapi_deallocate_address
// Requires: unregister_unixsocket_id
function pcl_jsapi_deallocate_address(unixsocket_id, on_success_callback, on_failure_callback) {
    unregister_unixsocket_id(unixsocket_id).then(function (_) {
        on_success_callback();
    }).catch(function (reason) {
        on_failure_callback(reason);
    });
}

// Function that connects to an address.
// It calls the on_success_callback with the unixsocket_id we are connected with to that address,
// or the failure_callback if some error occurred.
// Provide: pcl_jsapi_connect_to_address
// Requires: connect_to_unixsocket
function pcl_jsapi_connect_to_address(to_unixsocket_id, on_msg_callback, on_connection_to_callback, on_success_callback, on_failure_callback) {
    connect_to_unixsocket(to_unixsocket_id, on_msg_callback, on_connection_to_callback).then(function (from_unixsocket_id) {
        on_success_callback(from_unixsocket_id);
    }).catch(function (reason) {
        on_failure_callback(reason);
    });
}

// Function that sends a message from a unixsocket A to another unixsocket B.
// It must be that A and B are connected, either by A being the result of a connect_to_address(B) operation (then this is a client)
// or B is a client that connected to our socket A. (then this is the server)
// Provides: pcl_jsapi_send_msg
// Requires: PCL_VARS, PCL_CONSTS,
function pcl_jsapi_send_msg(from_unixsocket_id, to_unixsocket_id, msg, on_success_callback, on_failure_callback) {
    rtc_send_msg(from_unixsocket_id, to_unixsocket_id, msg).then(function (_) {
        on_success_callback();
    }).catch(function (reason) {
        on_failure_callback(reason);
    });
}

function pcl_jsapi_util_rand_str(length) {
    return make_random_id(length);
}

/** ------------------------------------------------   jsapi WITH CALLBACKS ------------------------------- */
/** ------------------------------------------------   jsapi WITH CALLBACKS ------------------------------- */
/** ------------------------------------------------   jsapi WITH CALLBACKS ------------------------------- */

/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONDITION_VARIABLES_STUFF ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
// Provides: create_promise
// Requires: PCL_VARS, PCL_CONSTS
function create_promise(name, reject_timeout) {
    reject_timeout = typeof reject_timeout !== 'undefined' ? reject_timeout : Infinity; // by default, no timeout

    var resolve_cp = null;
    var reject_cp = null;
    var promise = new Promise(function (resolve, reject) {
        resolve_cp = resolve;
        reject_cp = reject;

        // Set a timer to reject the promise on a timeout.
        if (reject_timeout < Infinity) {
            setTimeout(function() {
                try {
                    reject_promise(name, 'TIMEOUT!' + name);
                } catch(e) {
                    // might have already been resolved, ignore then.
                }
            }, reject_timeout);
        }
    });

    PCL_VARS.PROMISES_DICT[name] = {
      'promise': promise,
      'resolve': resolve_cp, 'reject': reject_cp, 'status': 'pending'
    };

    return promise;
}

// Provides: get_existing_promise
// Requires: PCL_VARS, PCL_CONSTS
function get_existing_promise(name) {
    if (!(name in PCL_VARS.PROMISES_DICT)) {
        throw "Promise does not exist " + name;
    }
    return PCL_VARS.PROMISES_DICT[name].promise;
}

// Provides: resolve_promise
// Requires: PCL_VARS, PCL_CONSTS
function resolve_promise(name, result) {
    if (!(name in PCL_VARS.PROMISES_DICT)) {
        throw "Promise does not exist " + name;
    }
    if (PCL_VARS.PROMISES_DICT[name].status === 'rejected') {
        throw "Promise was rejected!: " + name;
    }

    if (PCL_VARS.PROMISES_DICT[name].status === 'pending') {
        PCL_VARS.PROMISES_DICT[name].resolve(result);
    }
    PCL_VARS.PROMISES_DICT[name].status = 'resolved';
}

// Provides: reject_promise
// Requires: PCL_VARS, PCL_CONSTS
function reject_promise(name, reason) {
    if (!(name in PCL_VARS.PROMISES_DICT)) {
        throw "Promise does not exist " + name;
    }
    if (PCL_VARS.PROMISES_DICT[name].status === 'resolved') {
        throw "Promise was resolved!: " + name;
    }

    if (PCL_VARS.PROMISES_DICT[name].status === 'pending') {
        PCL_VARS.PROMISES_DICT[name].reject(reason);
    }
    PCL_VARS.PROMISES_DICT[name].status = 'rejected';
}
/** ------------------------------------------------------- CONDITION_VARIABLES_STUFF ------------------------------- */

/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {utils ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
// Provides: add_timeout_to_promise
// Requires: PCL_VARS, PCL_CONSTS
function add_timeout_to_promise(promise, timeout, msg) {
    return Promise.race([promise,
        new Promise(function (_, reject) {
            if (timeout < Infinity) {
                setTimeout(function () {
                    reject("TIMEOUT!" + msg);
                }, timeout);
            }
        })]);
}

// Provides: promise_name_for_register_unixsocket_id
// Requires: PCL_VARS, PCL_CONSTS
function promise_name_for_register_unixsocket_id(unixsocket_id) {
    return "promise_register_unixsocket_id_" + unixsocket_id;
}

// Provides: promise_name_for_unregister_unixsocket_id
// Requires: PCL_VARS, PCL_CONSTS
function promise_name_for_unregister_unixsocket_id(unixsocket_id) {
    return "promise_unregister_unixsocket_id_" + unixsocket_id;
}

// Provides: promise_name_from_msg_id_ack
// Requires: PCL_VARS, PCL_CONSTS
function promise_name_from_msg_id_ack(msg_id) {
    return "promise_ack_for_msg_id_" + msg_id;
}

// Provides: make_random_id
// Requires: PCL_VARS, PCL_CONSTS
function make_random_id(len) {
    var id = "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for (var i = 0; i < len; i++)
        id += alphabet.charAt(Math.floor(Math.random() * alphabet.length));

    return id;
}

// Provides: update_msg_count_and_get_unique_id
// Requires: PCL_VARS, PCL_CONSTS, make_random_id
function update_msg_count_and_get_unique_id() {
    PCL_VARS.TOTAL_MESSAGES_SENT += 1;
    return 'peer_unique_id_' + PCL_CONSTS.MY_UNIQUE_ID + '_msg_num_' + PCL_VARS.TOTAL_MESSAGES_SENT + '_id_' + make_random_id(8);
}

// Provides: get_unused_unixsocket_id
// Requires: PCL_VARS, PCL_CONSTS, make_random_id
function get_unused_unixsocket_id() {
    var _unixsocket_id = "none";
    do {
        _unixsocket_id = 'random_connect_unixsocket_id' + PCL_CONSTS.MY_UNIQUE_ID + make_random_id(10);
    } while (_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT);
    return _unixsocket_id;
}

// Provides: log_error
// Requires: PCL_VARS, PCL_CONSTS
function log_error(error) {
    console.log("%c \n\n----------------", "color: red");
    console.log("%c Got an error:", "color: red");
    console.log(error);
    if (typeof error !== 'undefined' && typeof error.stack !== 'undefined') {
        console.log(error.stack);
    }
    console.log("%c ----------------\n\n", "color: red");
}

// Provides: log_warning
// Requires: PCL_VARS, PCL_CONSTS
function log_warning(warning) {
    console.log("%c \n\n----------------", "color: yellow");
    console.log("%c Got a warning:", "color: yellow");
    console.log(warning);
    console.log("%c ----------------\n\n", "color: yellow");
}
/** ----------------------------------------------------------- {utils ------------------------------- */




// -------------------------------------------------------------- ******* TEST ******* //
function __pcljs_test() {
    start_pcl_layer("http://localhost:3000");
    var MY_SOCKET_ID = "peer_one_baby";
    var OTHER_SOCKET_ID = "peer_two_yeah";
    var MY_MESSAGE = "!!!HEY I AM PEER ONE 222211111112";

    register_unixsocket_id(MY_SOCKET_ID).then(function (_) {
        console.log('Successfully registered socket with id: ', MY_SOCKET_ID);

        console.log('About to sent message:', MY_MESSAGE);
        var msg_id = send_msg_to_unixsocket(MY_SOCKET_ID, OTHER_SOCKET_ID, MY_MESSAGE);
        console.log('Send with id:', msg_id);
        get_existing_promise(promise_name_from_msg_id_ack(msg_id)).then(function (_) {
            console.log('Got ACK for message', MY_MESSAGE, 'with id', msg_id);

        }, function (reason) {
            console.log('Failed to get ack with reason: ', reason);
        });
    }, function (reason) { console.log('Failed to register unixsocket_id', MY_SOCKET_ID, 'with reason', reason); });
}

// ---------------------------------------------------------------------- TEST