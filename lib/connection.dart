import 'dart:async';

import 'package:flutter_openvidu/flutter_openvidu.dart';
import 'package:flutter_webrtc/webrtc.dart';

enum ConnectionType { PUBLISH, RECEIVE }

class OpenViduConnection {
  RTCPeerConnection peerConnection;
  OpenVidu _openVidu;
  String id;
  MediaStream stream;
  RTCSignalingState _signalingState = RTCSignalingState.RTCSignalingStateStable;

  // 连接可用之前暂存ICE的集合
  final List<RTCIceCandidate> _iceCandidateList = [];

  // 连接类型
  final ConnectionType type;

  String sortId;

  OpenViduConnection(OpenVidu openVidu, String id, this.type) {
    _openVidu = openVidu;
    this.id = id;
    this.sortId = id.indexOf("_") != -1 ? id.substring(0, id.indexOf("_")) : id;
  }

  Future<RTCPeerConnection> init() async {
    this.peerConnection = await _createPeer();
    return peerConnection;
  }

  release() async {
    peerConnection.onRenegotiationNeeded = null;
    stream = null;
    if (stream != null) stream.dispose();
    peerConnection = null;
    if (peerConnection != null) peerConnection.close();
  }

  // 添加收到的ice信息
  addIceCandidate(RTCIceCandidate ice) {
    if (_signalingState == RTCSignalingState.RTCSignalingStateStable) {
      peerConnection.addCandidate(ice);
    } else {
      _iceCandidateList.add(ice);
    }
  }

  Future<RTCPeerConnection> _createPeer() async {
    var options = {
      "mandatory": {'OfferToReceiveAudio': true, 'OfferToReceiveVideo': true},
      "optional": [
        {"DtlsSrtpKeyAgreement": true}
      ]
    };
    var pc = await createPeerConnection(_openVidu.getIceConfig(), options);
    pc.onRenegotiationNeeded = _createOffer;
    pc.onIceCandidate = (RTCIceCandidate ice) {
      _openVidu.sendMessage("onIceCandidate", {
        "endpointName": sortId,
        "candidate": ice.candidate,
        "sdpMid": ice.sdpMid,
        "sdpMLineIndex": ice.sdpMlineIndex
      });
    };
    pc.onSignalingState = (RTCSignalingState state) {
      _signalingState = state;
      if (state == RTCSignalingState.RTCSignalingStateStable) {
        _iceCandidateList.forEach((ice) {
          pc.addCandidate(ice);
        });
        _iceCandidateList.clear();
      }
    };
    pc.addStream(_openVidu.localStream);
    return pc;
  }

  _createOffer() async {
    var sdp = await peerConnection.createOffer({
      'mandatory': {
        'OfferToReceiveAudio': !(type == ConnectionType.PUBLISH),
        'OfferToReceiveVideo': !(type == ConnectionType.PUBLISH),
      },
      "optional": [
        {"DtlsSrtpKeyAgreement": true},
      ],
    });
    await peerConnection.setLocalDescription(sdp);

    if (type == ConnectionType.PUBLISH) {
      _openVidu.sendMessage("publishVideo", {
        "sdpOffer": sdp.sdp,
        "doLoopback": false,
        "audio": true,
        "video": true,
        "audioActive": true,
        "videoActive": true,
        "typeOfVideo": "CAMERA",
        "frameRate": 30,
        "hasAudio": true,
        "hasVideo": true,
        "videoDimensions": '{"width":480,"height":640}'
      });
    } else {
      _openVidu.sendMessage("receiveVideoFrom", {
        "sender": id,
        "sdpOffer": sdp.sdp,
      });
    }
  }
}
