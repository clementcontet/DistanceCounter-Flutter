import 'dart:async';

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hardware_buttons/hardware_buttons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compteur distance',
      theme: ThemeData.dark(),
      home: Main(),
    );
  }
}

class Main extends StatefulWidget {
  @override
  _MainState createState() => _MainState();
}

class _MainState extends State<Main> with WidgetsBindingObserver {
  DateTime _computationStartTimeStamp;
  bool _streamsSubscribed = false;
  Position _lastPosition;
  String _bearing = "";
  int _correction = 100;
  double _stepCounter = 0;
  double _globalCounter = 0;
  StreamSubscription<Position> _positionStream;
  StreamSubscription _volumeButtonSubscription;
  final String correctionKey = "correction";
  final String globalCounterKey = "globalCounter";
  final Geolocator geolocator = Geolocator();
  Timer _longPressTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Wakelock.enable();
    _showPermissionStatus();
    _getValuesFromDisk();
    if (!_streamsSubscribed) {
      _lastPosition = null;
      _computationStartTimeStamp = DateTime.now().add(Duration(seconds: 5));
      _subscribeToPositionUpdates();
      _volumeButtonSubscription =
          volumeButtonEvents.listen((VolumeButtonEvent event) {
        setState(() {
          _stepCounter = 100000;
        });
      });
      _streamsSubscribed = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_streamsSubscribed) {
      _positionStream?.cancel();
      _volumeButtonSubscription?.cancel();
      _streamsSubscribed = false;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        Wakelock.enable();
        break;
      case AppLifecycleState.paused:
        Wakelock.disable();
        break;
      default:
    }
  }

  void _getValuesFromDisk() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _correction = prefs.getInt(correctionKey);
      _globalCounter = prefs.getDouble(globalCounterKey);
      if (_correction == null) {
        _correction = 100;
      }
      if (_globalCounter == null) {
        _globalCounter = 0;
      }
    });
  }

  void _storeValuesOnDisk() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setInt(correctionKey, _correction);
    prefs.setDouble(globalCounterKey, _globalCounter);
  }

  void _subscribeToPositionUpdates() {
    _positionStream = geolocator
        .getPositionStream(LocationOptions(
            accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 10))
        .listen((Position position) {
      if (position.timestamp.isBefore(_computationStartTimeStamp)) {
        _lastPosition = null;
        setState(() {
          _bearing = "..";
        });
      } else if (_lastPosition == null) {
        _lastPosition = position;
        setState(() {
          _bearing = "...";
        });
      } else if (_lastPosition.latitude != position.latitude ||
          _lastPosition.latitude != position.latitude) {
        double distance = computeDistance(_lastPosition.latitude,
            _lastPosition.longitude, position.latitude, position.longitude);
        int bearing = computeBearing(_lastPosition.latitude,
            _lastPosition.longitude, position.latitude, position.longitude);
        _lastPosition = position;
        setState(() {
          _bearing = "${bearing.toString()}°";
          _stepCounter += distance * _correction / 100;
          _globalCounter += distance * _correction / 100;
        });
        _storeValuesOnDisk();
      }
    });
  }

  Future<void> _showPermissionStatus() async {
    GeolocationStatus geolocationStatus =
        await geolocator.checkGeolocationPermissionStatus();
    String bearing = "";
    switch (geolocationStatus) {
      case GeolocationStatus.denied:
        bearing = "!!!";
        break;
      case GeolocationStatus.disabled:
        bearing = "N/A";
        break;
      case GeolocationStatus.granted:
        bearing = ".";
        break;
      case GeolocationStatus.restricted:
        bearing = "/!\\";
        break;
      case GeolocationStatus.unknown:
        bearing = "???";
        break;
    }
    setState(() {
      _bearing = bearing;
    });
  }

  void _incrementCounter(int numberOfMeters) {
    setState(() {
      _stepCounter = ((_stepCounter / numberOfMeters).floor().toDouble() + 1) *
          numberOfMeters;
      _globalCounter =
          ((_globalCounter / numberOfMeters).floor().toDouble() + 1) *
              numberOfMeters;
    });
    _storeValuesOnDisk();
  }

  void _decrementCounter(int numberOfMeters) {
    setState(() {
      _stepCounter = max(
          0,
          ((_stepCounter / numberOfMeters).ceil().toDouble() - 1) *
              numberOfMeters);
      _globalCounter = max(
          0,
          ((_globalCounter / numberOfMeters).ceil().toDouble() - 1) *
              numberOfMeters);
    });
    _storeValuesOnDisk();
  }

  void _setCorrection(int correction) {
    setState(() {
      _correction = correction;
    });
    _storeValuesOnDisk();
  }

  void showCorrectionOptions() {
    showDialog(
        context: context,
        builder: (BuildContext context) {
          return CorrectionOptions(
              widgetCorrection: _correction,
              widgetSetCorrection: _setCorrection);
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              showCorrectionOptions();
            },
          ),
        ],
        title: Center(
            child: Text(
          _bearing,
          style: Theme.of(context).textTheme.display3,
        )),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                GestureDetector(
                  onLongPressStart: (LongPressStartDetails details) {
                    _longPressTimer = Timer.periodic(Duration(seconds: 1),
                        (Timer t) => _decrementCounter(100));
                  },
                  onLongPressEnd: (LongPressEndDetails details) {
                    _longPressTimer?.cancel();
                  },
                  child: IconButton(
                    onPressed: () {
                      _decrementCounter(10);
                    },
                    icon: Icon(Icons.remove),
                    iconSize: 96,
                  ),
                ),
                GestureDetector(
                  onLongPressStart: (LongPressStartDetails details) {
                    _longPressTimer = Timer.periodic(Duration(seconds: 1),
                            (Timer t) => _incrementCounter(100));
                  },
                  onLongPressEnd: (LongPressEndDetails details) {
                    _longPressTimer?.cancel();
                  },
                  child: IconButton(
                    onPressed: () {
                      _incrementCounter(10);
                    },
                    icon: Icon(Icons.add),
                    iconSize: 96,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _stepCounter = 0;
                });
              },
              child: Text(
                '${(_stepCounter / 1000).toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 80),
              ),
            ),
            GestureDetector(
              onLongPress: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: new Text("Remise à zéro du compteur général ?"),
                      actions: <Widget>[
                        FlatButton(
                          child: Text("Annuler"),
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        ),
                        FlatButton(
                          child: Text("OK"),
                          onPressed: () {
                            setState(() {
                              _globalCounter = 0;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ],
                    );
                  },
                );
              },
              child: Text(
                '${(_globalCounter / 1000).toStringAsFixed(2)}',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 80),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CorrectionOptions extends StatefulWidget {
  final int widgetCorrection;
  final widgetSetCorrection;

  CorrectionOptions(
      {Key key,
      @required this.widgetCorrection,
      @required this.widgetSetCorrection})
      : super(key: key);

  @override
  _CorrectionOptionsState createState() =>
      _CorrectionOptionsState(widgetCorrection, widgetSetCorrection);
}

class _CorrectionOptionsState extends State<CorrectionOptions> {
  int dialogCorrection;
  var dialogSetCorrection;

  _CorrectionOptionsState(this.dialogCorrection, this.dialogSetCorrection);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correction de distance :'),
      content: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          IconButton(
            icon: Icon(Icons.remove),
            iconSize: 40,
            onPressed: () {
              setState(() {
                dialogCorrection--;
              });
              dialogSetCorrection(dialogCorrection);
            },
          ),
          Text(
            '$dialogCorrection %',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 28),
          ),
          IconButton(
            icon: Icon(Icons.add),
            iconSize: 40,
            onPressed: () {
              setState(() {
                dialogCorrection++;
              });
              dialogSetCorrection(dialogCorrection);
            },
          ),
        ],
      ),
    );
  }
}

double computeDistance(lat1, lon1, lat2, lon2) {
  // See http://www.movable-type.co.uk/scripts/latlong.html
  var R = 6371e3;
  var phi1 = toRadians(lat1);
  var phi2 = toRadians(lat2);
  var lambda1 = toRadians(lon1);
  var lambda2 = toRadians(lon2);
  var deltaPhi = phi2 - phi1;
  var deltaLambda = lambda2 - lambda1;
  var a = sin(deltaPhi / 2) * sin(deltaPhi / 2) +
      cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2);
  var c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return R * c;
}

int computeBearing(lat1, lon1, lat2, lon2) {
  // See http://www.movable-type.co.uk/scripts/latlong.html
  var phi1 = toRadians(lat1);
  var phi2 = toRadians(lat2);
  var lambda1 = toRadians(lon1);
  var lambda2 = toRadians(lon2);
  var deltaLambda = lambda2 - lambda1;
  var y = sin(deltaLambda) * cos(phi2);
  var x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(deltaLambda);
  var bearing = toDegrees(atan2(y, x));
  return (bearing + 360).round() % 360;
}

double toRadians(value) {
  return value * pi / 180;
}

double toDegrees(value) {
  return value / pi * 180;
}
