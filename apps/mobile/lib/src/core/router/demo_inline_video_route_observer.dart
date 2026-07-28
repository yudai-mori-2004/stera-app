import "package:flutter/widgets.dart";

/// Drives [RouteAware] in [DemoVideoInlinePreview] so playback pauses when a
/// new route covers the shell (e.g. fullscreen demo, profile).
final RouteObserver<ModalRoute<dynamic>> demoInlineVideoRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();
