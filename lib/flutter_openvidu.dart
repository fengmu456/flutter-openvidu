import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/webrtc.dart';

import 'connection.dart';

export 'connection.dart';
export 'openvidu_video_view.dart';
export 'package:flutter_webrtc/webrtc.dart';

void debug(String name, data) {
  print("========== ${name} ==========");
  print(data);
}

enum CONNECTION_CHANGE_TYPE { CREATE, DESTROY }

typedef ConnectionChangeCallback = Function(
  OpenViduConnection conn,
  CONNECTION_CHANGE_TYPE type,
);

class OpenVidu {
  Map<String, dynamic> mediaConstraints = {
    "audio": true,
    "video": {
      "mandatory": {
        "width": "480",
        "height": "640",
        "minFrameRate": 30,
      },
      "facingMode": "user",
      "optional": [],
    }
  };
  String _token = "";
  String _sessionName = "";
  WebSocket _webSocket;
  int _msgId = 0;
  String _turnUsername = "";
  String _turnCredential = "";
  Map<String, OpenViduConnection> connections = new Map();
  OpenViduConnection localConnection;
  Timer _timer;
  MediaStream localStream;
  Map<int, String> _answerMap = Map();

  final String wssClientServer;
  final String turnServer;
  final ConnectionChangeCallback connectionChangeCallback;

  OpenVidu({
    this.wssClientServer,
    this.turnServer,
    this.connectionChangeCallback,
  });

  sendMessage(String method, Map<String, dynamic> data) {
    // 解决sdpAnswer消息返回不带id的问题，用msgId做映射
    if (method == "receiveVideoFrom") {
      _answerMap[_msgId] = data["sender"];
    }
    _webSocket.add(jsonEncode({
      "jsonrpc": "2.0",
      "id": _msgId++,
      "method": method,
      "params": data,
    }));
  }

  OpenViduConnection getConnectionById(String id) {
    var sortId = id.indexOf("_") != -1 ? id.substring(0, id.indexOf("_")) : id;
    return connections[sortId];
  }

  void join(String sessionName, String token, metadata) async {
    localStream = await navigator.getUserMedia(mediaConstraints);
    debug("获取本地视频", localStream.id);
    var tokenParams = {};
    String query = token.substring(token.indexOf("?") + 1);
    query.split("&").forEach((String str) {
      var kv = str.split("=");
      tokenParams[kv[0]] = kv.length > 1 ? kv[1] : kv[0];
    });
    _token = token;
    _sessionName = sessionName;
    _webSocket = await WebSocket.connect(wssClientServer);
    _turnUsername = tokenParams["turnUsername"];
    _turnCredential = tokenParams["turnCredential"];
    _webSocket.listen(_onReceiveMessage);
    sendMessage("ping", {"interval": 5000});
    sendMessage("joinRoom", {
      "token": _token,
      "session": _sessionName,
      "metadata": jsonEncode(metadata),
      "platform": "Flutter ${Platform.operatingSystem}",
      "secret": "",
      "recorder": false
    });
    _timer = new Timer.periodic(new Duration(seconds: 5), (Timer timer) async {
      sendMessage("ping", {});
    });
  }

  _publishVideo(String id) async {
    localConnection = new OpenViduConnection(this, id, ConnectionType.PUBLISH);
    connections[localConnection.sortId] = localConnection;
    await localConnection.init();
    localConnection.stream = localStream;
    notifyConnection(localConnection, CONNECTION_CHANGE_TYPE.CREATE);
  }

  _receiveVideo(member) async {
    if (member["streams"] == null ||
        member["streams"][0] == null ||
        member["streams"][0]["id"] == null) {
      return;
    }

    String id = member["streams"][0]["id"];
    OpenViduConnection connection = new OpenViduConnection(
      this,
      id,
      ConnectionType.RECEIVE,
    );
    connections[connection.sortId] = connection;
    RTCPeerConnection pc = await connection.init();
    pc.onAddStream = (MediaStream stream) {
      OpenViduConnection connection = getConnectionById(id);
      connection.stream = stream;
      notifyConnection(connection, CONNECTION_CHANGE_TYPE.CREATE);
    };
  }

  getIceConfig() {
    return {
      'iceServers': [
        {
          "urls": ['stun:$turnServer']
        },
        {
          "urls": ['turn:$turnServer', 'turn:$turnServer?transport=tcp'],
          "username": _turnUsername,
          "credential": _turnCredential
        }
      ]
    };
  }

  void clear() {
    connections.forEach((id, connection) async {
      await connection.peerConnection.dispose();
    });
  }

  exit() async {
    if (_timer != null) _timer.cancel();
    if (_webSocket != null) {
      sendMessage("leaveRoom", {});
      _webSocket.close();
      _webSocket = null;
    }
    _token = null;
    _sessionName = null;
    _turnUsername = null;
    _turnCredential = null;
    connections.forEach((id, conn) {
      conn.release();
      notifyConnection(conn, CONNECTION_CHANGE_TYPE.DESTROY);
    });
    connections.clear();
    localConnection = null;
    localStream = null;
  }

  void _onReceiveMessage(msg) async {
    msg = jsonDecode(msg);
    debug("收到消息", msg);
    var result = msg["result"];
    if (result != null) {
      if (result["sdpAnswer"] != null) {
        _saveAnswer(msg);
      } else if (result["sessionId"] != null && result["value"] != null) {
        // joinRoom 返回结果
        List members = result["value"];
        members.forEach(_receiveVideo);
        await _publishVideo(result["id"]);
      } else if (result["value"] != null) {
        // 收到PONG
      } else {
        debug("未知消息", msg);
      }
    }
    if (msg["method"] == "iceCandidate") {
      print(msg);
      _onIceCandidate(msg);
    }
    if (msg["method"] == "participantJoined") {
      print(msg["params"]);
      // receiveVideo(msg["params"]);
    }
    if (msg["method"] == "participantPublished") {
      _receiveVideo(msg["params"]);
      print(msg);
    }
    if (msg["method"] == "participantLeft") {
      debug('参与者离开', msg["params"]["connectionId"]);
      var connection = connections[msg["params"]["connectionId"]];
      connections.remove(connection);
      await connection.release();
      notifyConnection(connection, CONNECTION_CHANGE_TYPE.DESTROY);
    }
  }

  _onIceCandidate(msg) async {
    var iceParams = msg["params"];
    var id = iceParams["endpointName"];
    var ice = new RTCIceCandidate(
      iceParams["candidate"],
      iceParams["sdpMid"],
      iceParams["sdpMLineIndex"],
    );
    var connection = connections[id];
    connection.addIceCandidate(ice);
  }

  _saveAnswer(msg) async {
    String id = msg["result"]["id"];
    if (id == null) id = _answerMap[msg["id"]];
    OpenViduConnection connection = getConnectionById(id);
    _answerMap.remove(msg["id"]);
    var sdp = new RTCSessionDescription(msg["result"]["sdpAnswer"], "answer");
    connection.peerConnection.setRemoteDescription(sdp);
  }

  sleep(val) {
    return Future.delayed(Duration(seconds: val));
  }

  notifyConnection(OpenViduConnection conn, CONNECTION_CHANGE_TYPE type) {
    if (connectionChangeCallback != null) {
      connectionChangeCallback(conn, type);
    }
  }
}
