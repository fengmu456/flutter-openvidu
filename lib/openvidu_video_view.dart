import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/media_stream.dart';
import 'package:flutter_webrtc/utils.dart';

enum VideoViewObjectFit {
  VideoViewObjectFitContain,
  VideoViewObjectFitCover,
}

class VideoRenderer {
  MethodChannel _channel = WebRTC.methodChannel();
  int _textureId;
  int _rotation = 0;
  double _width = 0.0,
      _height = 0.0;
  bool _mirror;
  MediaStream _srcObject;
  StreamSubscription<dynamic> _eventSubscription;
  dynamic onFirstFrameRendered;

  initialize() async {
    final Map<dynamic, dynamic> response =
    await _channel.invokeMethod('createVideoRenderer', {});
    _textureId = response['textureId'];
    _eventSubscription = _eventChannelFor(_textureId)
        .receiveBroadcastStream()
        .listen(eventListener, onError: errorListener);
  }

  int get rotation => _rotation;

  double get width => _width;

  double get height => _height;

  int get textureId => _textureId;

  set mirror(bool mirror) {
    _mirror = mirror;
  }

  set srcObject(MediaStream stream) {
    _srcObject = stream;
    _channel.invokeMethod('videoRendererSetSrcObject', <String, dynamic>{
      'textureId': _textureId,
      'streamId': stream != null ? stream.id : ''
    });
  }

  Future<Null> dispose() async {
    await _channel.invokeMethod(
      'videoRendererDispose',
      <String, dynamic>{'textureId': _textureId},
    );
  }

  EventChannel _eventChannelFor(int textureId) {
    return new EventChannel('cloudwebrtc.com/WebRTC/Texture$textureId');
  }

  void eventListener(dynamic event) {
    final Map<dynamic, dynamic> map = event;
    switch (map['event']) {
      case 'didTextureChangeRotation':
        _rotation = map['rotation'];
        break;
      case 'didTextureChangeVideoSize':
        _width = map['width'];
        _height = map['height'];
        break;
      case 'didFirstFrameRendered':
        if (this.onFirstFrameRendered != null) this.onFirstFrameRendered();
        break;
    }
  }

  void errorListener(Object obj) {
    final PlatformException e = obj;
    throw e;
  }
}

class VideoView extends StatefulWidget {
  final VideoRenderer renderer;
  final aspectRatio;

  VideoView(this.renderer, this.aspectRatio);

  @override
  _VideoViewState createState() => new _VideoViewState(renderer);
}

class _VideoViewState extends State<VideoView> {
  final VideoRenderer renderer;

  _VideoViewState(this.renderer);

  @override
  void initState() {
    super.initState();
  }

  @override
  void deactivate() {
    super.deactivate();
    renderer.onFirstFrameRendered = null;
  }

  @override
  Widget build(BuildContext context) {
    return new Center(
        child: (this.renderer._textureId == null ||
            this.renderer._srcObject == null)
            ? new Container()
            : new AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: new Texture(
            textureId: this.renderer._textureId,
          ),
        ));
  }
}
