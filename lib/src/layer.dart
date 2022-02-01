import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/plugin_api.dart';
import 'package:latlong2/latlong.dart';

import 'center_on_location_update.dart';
import 'data.dart';
import 'drawing/heading_sector.dart';
import 'layer_options.dart';
import 'plugin.dart';
import 'tween.dart';

class LocationMarkerLayer extends StatefulWidget {
  final LocationMarkerPlugin plugin;
  final LocationMarkerLayerOptions locationMarkerOpts;
  final MapState map;
  final Stream<Null> stream;

  LocationMarkerLayer(
    this.plugin,
    this.locationMarkerOpts,
    this.map,
    this.stream,
  ) : super(
          key: locationMarkerOpts.key,
        );

  @override
  _LocationMarkerLayerState createState() => _LocationMarkerLayerState();
}

class _LocationMarkerLayerState extends State<LocationMarkerLayer>
    with TickerProviderStateMixin {
  late bool _isFirstLocationUpdate;
  LocationMarkerPosition? _currentPosition;
  late StreamSubscription<LocationMarkerPosition> _positionStreamSubscription;

  /// A stream for centering single that also include a zoom level
  StreamSubscription<double>? _centerCurrentLocationStreamSubscription;
  AnimationController? _animationController;

  @override
  void initState() {
    super.initState();
    _isFirstLocationUpdate = true;
    _positionStreamSubscription =
        widget.locationMarkerOpts.positionStream.listen(_handlePositionUpdate);
    _centerCurrentLocationStreamSubscription =
        widget.plugin.centerCurrentLocationStream?.listen((double zoom) {
      if (_currentPosition != null) {
        _moveMap(
            LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom);
      }
    });
  }

  @override
  void didUpdateWidget(LocationMarkerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.locationMarkerOpts.positionStream !=
        oldWidget.locationMarkerOpts.positionStream) {
      _positionStreamSubscription.cancel();
      _positionStreamSubscription = widget.locationMarkerOpts.positionStream
          .listen(_handlePositionUpdate);
    }
  }

  @override
  void dispose() {
    _positionStreamSubscription.cancel();
    _centerCurrentLocationStreamSubscription?.cancel();
    _animationController?.dispose();
    super.dispose();
  }

  void _handlePositionUpdate(LocationMarkerPosition position) {
    setState(() => _currentPosition = position);

    bool centerCurrentLocation;
    switch (widget.plugin.centerOnLocationUpdate) {
      case CenterOnLocationUpdate.always:
        centerCurrentLocation = true;
        break;
      case CenterOnLocationUpdate.once:
        centerCurrentLocation = _isFirstLocationUpdate;
        _isFirstLocationUpdate = false;
        break;
      case CenterOnLocationUpdate.never:
        centerCurrentLocation = false;
        break;
    }
    if (centerCurrentLocation) {
      _moveMap(LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          widget.map.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition != null) {
      if (widget.locationMarkerOpts.markerAnimationDuration == Duration.zero) {
        return _buildLocationMarker(_currentPosition!);
      } else {
        return TweenAnimationBuilder(
          tween: LocationMarkerPositionTween(
              begin: _currentPosition!, end: _currentPosition!),
          duration: widget.locationMarkerOpts.markerAnimationDuration,
          builder: (BuildContext context, LocationMarkerPosition position,
              Widget? child) {
            return _buildLocationMarker(position);
          },
        );
      }
    } else {
      return SizedBox.shrink();
    }
  }

  Widget _buildLocationMarker(LocationMarkerPosition position) {
    final latLng = position.latLng;
    final diameter = widget.locationMarkerOpts.headingSectorRadius * 2;
    return GroupLayer(
      GroupLayerOptions(
        group: [
          if (widget.locationMarkerOpts.showAccuracyCircle)
            CircleLayerOptions(
              circles: [
                CircleMarker(
                  point: latLng,
                  radius: position.accuracy,
                  useRadiusInMeter: true,
                  color: widget.locationMarkerOpts.accuracyCircleColor,
                ),
              ],
            ),
          MarkerLayerOptions(
            markers: [
              if (widget.locationMarkerOpts.showHeadingSector)
                Marker(
                  point: latLng,
                  width: diameter,
                  height: diameter,
                  builder: (_) {
                    return IgnorePointer(
                      ignoring: true,
                      child: StreamBuilder(
                        stream: widget.locationMarkerOpts.headingStream,
                        builder: (BuildContext context,
                            AsyncSnapshot<LocationMarkerHeading> snapshot) {
                          if (snapshot.hasData) {
                            return TweenAnimationBuilder(
                                tween: LocationMarkerHeadingTween(
                                  begin: snapshot.data!,
                                  end: snapshot.data!,
                                ),
                                duration: widget
                                    .locationMarkerOpts.markerAnimationDuration,
                                builder: (BuildContext context,
                                    LocationMarkerHeading heading,
                                    Widget? child) {
                                  return CustomPaint(
                                    size: Size.fromRadius(widget
                                        .locationMarkerOpts
                                        .headingSectorRadius),
                                    painter: HeadingSector(
                                      widget.locationMarkerOpts
                                          .headingSectorColor,
                                      snapshot.data!.heading,
                                      snapshot.data!.accuracy,
                                    ),
                                  );
                                });
                          } else {
                            return SizedBox.shrink();
                          }
                        },
                      ),
                    );
                  },
                ),
              Marker(
                point: latLng,
                width: widget.locationMarkerOpts.markerSize.width,
                height: widget.locationMarkerOpts.markerSize.height,
                builder: (_) => widget.locationMarkerOpts.marker,
              ),
            ],
          ),
        ],
      ),
      widget.map,
      widget.stream,
    );
  }

  void _moveMap(LatLng latLng, double zoom) {
    _animationController?.dispose();
    _animationController = AnimationController(
      duration: widget.plugin.centerAnimationDuration,
      vsync: this,
    );
    final animation = CurvedAnimation(
      parent: _animationController!,
      curve: Curves.fastOutSlowIn,
    );
    final latTween = Tween(
      begin: widget.map.center.latitude,
      end: latLng.latitude,
    );
    final lngTween = Tween(
      begin: widget.map.center.longitude,
      end: latLng.longitude,
    );
    final zoomTween = Tween(
      begin: widget.map.zoom,
      end: zoom,
    );

    _animationController!.addListener(() {
      widget.map.move(
        LatLng(
          latTween.evaluate(animation),
          lngTween.evaluate(animation),
        ),
        zoomTween.evaluate(animation),
        source: MapEventSource.mapController,
      );
    });

    _animationController!.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _animationController!.dispose();
        _animationController = null;
      }
    });

    _animationController!.forward();
  }
}