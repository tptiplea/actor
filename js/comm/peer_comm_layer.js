const SERVER_URL = "http://localhost:3000";  // TODO: add the server URL here


//* CONSTANTS **////
const PCL_CONSTS = {
    MY_UNIQUE_ID : make_random_id(10),
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
var PCL_VARS = {
    IOSOCKET : io(SERVER_URL),
    TOTAL_MESSAGES_SENT : 0,
    UNIXSOCKET_ID_TO_WEBRTC_DICT : {}, // keep track of unixsocket ids bound on this server
    PROMISES_DICT : {}, // keep track of promises
    RTC_UNIXSOCKET_IN_Q : {} // keep messages. map[id].msg_q = queue of msgs, map[id].consumer_q = queue of promise resolvers
};
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************
////**************************************************************** VARIABLES **********************************

// Connect to server.
PCL_VARS.IOSOCKET.on('server_to_peer', process_msg_from_server);

// The semaphore that tells us whether we're connected to the server.
create_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME, 5 * 60 * 1000); // Timeout if we don't connect to server in that time.
get_existing_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
    console.log('CONNECTED TO IO SERVER, got id:', PCL_CONSTS.MY_UNIQUE_ID);
});


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET send stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
// Send a msg to server, return a promise after that is done.
function send_msg_to_server(msg) {
    return get_existing_promise(PCL_CONSTS.CONNECTED_TO_SERVER_PROMISE_NAME).then(function (_) {
        PCL_VARS.IOSOCKET.emit('peer_to_server', msg);
    });
}
/** ------------------------------------------------ IOSOCKET send stuff} ------------------------------- */



/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ {IOSOCKET receive stuff ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ */
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
function register_unixsocket_id(unixsocket_id) {
    if (unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT) {
        throw "Unixsocket with id " + unixsocket_id + " already bound";
    }
    PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[unixsocket_id] = {}; // all the sockets we are connected to.
    PCL_VARS.RTC_UNIXSOCKET_IN_Q[unixsocket_id] = {
        'msg_q' : [],
        'consumer_q' : []
    };

    var promise_name = promise_name_for_register_unixsocket_id(unixsocket_id);
    send_msg_to_server({
        'kind': PCL_CONSTS.PEER_TO_SERVER_KIND,
        'operation': PCL_CONSTS.REGISTER_UNIXSOCKET_OP,
        'unixsocket_id': unixsocket_id
    });

    return create_promise(promise_name, 10 * 1000);
}

function unregister_unixsocket_id(unixsocket_id) {
    if (!(unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT)) {
        throw "Unixsocket with id " + unixsocket_id + " not bound!";
    }
    delete PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[unixsocket_id];

    var promise_name = promise_name_for_unregister_unixsocket_id(unixsocket_id);
    send_msg_to_server({
        'kind': PCL_CONSTS.PEER_TO_SERVER_KIND,
        'operation': PCL_CONSTS.UNREGISTER_UNIXSOCKET_OP,
        'unixsocket_id': unixsocket_id
    });

    return create_promise(promise_name, 10 * 1000);
}


/** --------------------------- REGISTER/UNREGISTER UNIXSOCKETS --------------------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ PEER_TO_PEER_MSG ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/

// id, from this socket, send it to
function send_ack_to_unixsocket(msg_id, from_unixsocket_id, to_unixsocket_id) {
    send_msg_to_server({
       'kind': PCL_CONSTS.PEER_TO_PEER_KIND,
       'operation': PCL_CONSTS.ACK_OP,
        'result': PCL_CONSTS.OK_STATUS,
        'msg_id': msg_id,
        'to_unixsocket_id': to_unixsocket_id,
        'from_unixsocket_id': from_unixsocket_id
    });
}

function process_msg_from_unixsocket(from_unixsocket_id, to_unixsocket_id, payload, msg_id) {
    if (!(to_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT)) {
        console.log('ERROR!!!: Got a message for an unregistered unixsocket_id, dropping it.');
        throw "Message for UNREGISTERED UNIXSOCKET ID";
    }
    // Pretty much always ack the message first.
    var other_unixsocket_id = from_unixsocket_id; // to other
    var me_unixsocket_id = to_unixsocket_id; // from me (reverse)
    send_ack_to_unixsocket(msg_id, me_unixsocket_id, other_unixsocket_id);
    // ---------

    if ((typeof payload !== 'object')
        || (!('webrtc_type' in payload))
        || payload.webrtc_type !== PCL_CONSTS.RTC_ICECANDIDATE
        || payload.webrtc_type !== PCL_CONSTS.RTC_DESCRIPTION) {
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

// Set up an RTCPeerConnection and a DataChannel between these two sockets.
// Returns a promise resolved when the data channel is open.
function set_up_rtcpeerconnection(me_unixsocket_id, other_unixsocket_id, am_caller) {
    var resolver = null;
    var open_channel_promise = add_timeout_to_promise(new Promise(function (resolve, _) {resolver = resolve;},
        60 * 1000,'Setting up the RTCPEERCONNECTION TIMEDOUT'));

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

        }).catch(log_error);
    };

    function handle_new_datachannel(channel) {
        channel.onopen = function (_) {
            resolver(channel); // resolve the promise when we get the channel open.
        };

        channel.onclose = function (_) {
            console.log('Datachannel between', other_unixsocket_id, 'and', me_unixsocket_id, 'has closed down');
        };
        
        channel.onmessage = function (event) {
            rtc_process_received_message(other_unixsocket_id, me_unixsocket_id, event.data);
        }
    }

    pc.onclose = function (_) {
        console.log('RTCPeerConnection between', other_unixsocket_id, 'and', me_unixsocket_id, 'has closed down');
    };

    if (am_caller) {
        handle_new_datachannel(pc.createDataChannel(me_unixsocket_id + other_unixsocket_id));
    } else {
        pc.ondatachannel = handle_new_datachannel;
    }

    return open_channel_promise;
}

// Connect to this socket.
function connect_to_unixsocket(to_unixsocket_id) {
    var from_unixsocket_id = get_unused_unixsocket_id();
    // This will contain the result of the connection, either the from_unixsocket_id connected to this
    // Or a failure.

    // Register the listening unixsocket.
    register_unixsocket_id(from_unixsocket_id).then(function (_) {
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
function rtc_process_received_message(from_unixsocket_id, to_unixsocket_id, msg) {
    var msg_with_src = {
        'msg': msg,
        'from_unixsocket_id': from_unixsocket_id
    };
    if (PCL_VARS.RTC_UNIXSOCKET_IN_Q[to_unixsocket_id].consumer_q.length === 0) {
        // no one waiting for a message, queue it.
        PCL_VARS.RTC_UNIXSOCKET_IN_Q[to_unixsocket_id].msg_q.push(msg_with_src);
    } else {
        // Otherwise, send it to the consumer.
        var resolver = PCL_VARS.RTC_UNIXSOCKET_IN_Q[to_unixsocket_id].consumer_q.pop();
        resolver(msg_with_src);
    }
}

// Send a message over the rtc channel.
function rtc_send_msg(from_unixsocket_id, to_unixsocket_id, msg) {
    if (!(to_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[from_unixsocket_id])) {
        var error_msg = "ERROR: " + "The local socket -" + from_unixsocket_id +
            "- is not connected to remote socket-" + to_unixsocket_id + "!";
        console.log(error_msg);
        return Promise.reject(error_msg);
    }

    var open_channel_promise = PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT[from_unixsocket_id][to_unixsocket_id].channel_promise;

    return open_channel_promise.then(function (channel) {
        channel.send(msg);
    });
}

function rtc_get_msg_sync(unixsocket_id) {
    if (!(unixsocket_id in PCL_VARS.RTC_UNIXSOCKET_IN_Q)) {
        var err_msg = "Unixsocket with id:" + unixsocket_id + "not registered with server.";
        console.log(err_msg);
        return Promise.reject(err_msg);
    }

    if (PCL_VARS.RTC_UNIXSOCKET_IN_Q[unixsocket_id].msg_q.length === 0) {
        // No messages available, wait for them.
        return add_timeout_to_promise(new Promise(function (resolve, _) {
            PCL_VARS.RTC_UNIXSOCKET_IN_Q[unixsocket_id].consumer_q.push(resolve);
        }), 10 * 60 * 1000);
    } else {
        // A message available, return it now.
        var msg = PCL_VARS.RTC_UNIXSOCKET_IN_Q[unixsocket_id].msg_q.pop();
        return Promise.resolve(msg);
    }
}

/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */
/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */
/** ------------------------------------------------  WEBRTC_SEND_RECV ------------------------------- */


/** ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ CONDITION_VARIABLES_STUFF ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^*/
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

function get_existing_promise(name) {
    if (!(name in PCL_VARS.PROMISES_DICT)) {
        throw "Promise does not exist " + name;
    }
    return PCL_VARS.PROMISES_DICT[name].promise;
}

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
function add_timeout_to_promise(promise, timeout, msg) {
    return Promise.race([promise, function (_, reject) {
        if (timeout < Infinity) {
            setTimeout(function () {
                reject("TIMEOUT!" + msg);
            }, timeout);
        }
    }]);
}

function promise_name_for_register_unixsocket_id(unixsocket_id) {
    return "promise_register_unixsocket_id_" + unixsocket_id;
}

function promise_name_for_unregister_unixsocket_id(unixsocket_id) {
    return "promise_unregister_unixsocket_id_" + unixsocket_id;
}

function promise_name_from_msg_id_ack(msg_id) {
    return "promise_ack_for_msg_id_" + msg_id;
}

function make_random_id(len) {
    var id = "";
    const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

    for (var i = 0; i < len; i++)
        id += alphabet.charAt(Math.floor(Math.random() * alphabet.length));

    return id;
}

function update_msg_count_and_get_unique_id() {
    PCL_VARS.TOTAL_MESSAGES_SENT += 1;
    return 'peer_unique_id_' + PCL_CONSTS.MY_UNIQUE_ID + '_msg_num_' + PCL_VARS.TOTAL_MESSAGES_SENT + '_id_' + make_random_id(8);
}

function get_unused_unixsocket_id() {
    var _unixsocket_id = "none";
    do {
        _unixsocket_id = 'random_connect_unixsocket_id' + PCL_CONSTS.MY_UNIQUE_ID + make_random_id(10);
    } while (_unixsocket_id in PCL_VARS.UNIXSOCKET_ID_TO_WEBRTC_DICT);
    return _unixsocket_id;
}

function log_error(error) {
    console.log("\n\n----------------");
    console.log("Got an error:");
    console.log(error);
    console.log("----------------\n\n");
}
/** ----------------------------------------------------------- {utils ------------------------------- */




// -------------------------------------------------------------- ******* TEST ******* //

function test() {
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

function test2() {
    var am_server = true;
    var SERVER_SOCKET_ID = "unixsocket_for_server";

    if (am_server) {
        console.log('I AM SERVER, binding address ', SERVER_SOCKET_ID);
        register_unixsocket_id(SERVER_SOCKET_ID).then(function (_) {
            return rtc_get_msg_sync(SERVER_SOCKET_ID);
        }).then(function (msg) {
            var from_unixsocket_id = msg.from_unixsocket_id;
            var msg = msg.msg;
            console.log('SERVER: Got message', msg, 'from client with socket id', from_unixsocket_id);

            rtc_send_msg(SERVER_SOCKET_ID, from_unixsocket_id, 'HI THERE CLIENT, thanks for msg - ' + msg);
            console.log('SERVER IS DONE');
        });
    } else {
        console.log('I AM CLIENT, waiting to connect to server');
        connect_to_unixsocket(SERVER_SOCKET_ID).then(function (my_socket_id) {
            console.log('I am client, connected to server with my socket', my_socket_id);
            rtc_send_msg(my_socket_id, SERVER_SOCKET_ID, 'HI Server, I am client with id' + my_socket_id);
            return rtc_get_msg_sync(my_socket_id);
        }).then(function (msg) {
            var from_unixsocket_id = msg.from_unixsocket_id;
            var msg = msg.msg;
            console.log('CLIENT: Got message', msg, 'from server with socket id', from_unixsocket_id);
            console.log('The from should be the same as socket:', from_unixsocket_id === SERVER_SOCKET_ID);
            console.log('CLIENT: I am done');
        });
    }
}

test2();

// ---------------------------------------------------------------------- TEST