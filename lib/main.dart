import 'dart:async';

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:hardware_buttons/hardware_buttons.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Compteur distance',
      theme: ThemeData(
        primarySwatch: Colors.grey,
      ),
      home: Main(),
    );
  }
}

class Main extends StatefulWidget {
  @override
  _MainState createState() => _MainState();
}

class _MainState extends State<Main> with WidgetsBindingObserver {
  double _correction = 1;
  String correctionKey = "correction";
  double _stepCounter = 0;
  double _globalCounter = 0;
  String globalCounterKey = "globalCounter";
  StreamSubscription _volumeButtonSubscription;
  final Geolocator geolocator = Geolocator()..forceAndroidLocationManager;
  StreamSubscription<Position> _positionStream;
  Position _lastPosition;
  String _bearing = "---°";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getValuesFromDisk();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        print("app resumed");
        _volumeButtonSubscription =
            volumeButtonEvents.listen((VolumeButtonEvent event) {
          if (event == VolumeButtonEvent.VOLUME_UP) {
            _incrementCounter(100);
          } else {
            _decrementCounter(100);
          }
        });

        _positionStream = geolocator
            .getPositionStream(LocationOptions(
                accuracy: LocationAccuracy.best, distanceFilter: 5))
            .listen((Position position) {
          print("new position with last available ${_lastPosition != null}");
          if (_lastPosition == null) {
            _lastPosition = position;
          } else {
            double distance = computeDistance(_lastPosition.latitude,
                _lastPosition.longitude, position.latitude, position.longitude);
            print("distance computed ${distance}");
            int bearing = computeBearing(_lastPosition.latitude,
                _lastPosition.longitude, position.latitude, position.longitude);
            _lastPosition = position;
            setState(() {
              _bearing = "${bearing.toString()}°";
              _stepCounter += distance * _correction;
              _globalCounter += distance * _correction;
            });
            _storeValuesOnDisk();
          }
        });
        break;

      case AppLifecycleState.paused:
        print("app paused");
        _lastPosition = null;
        _volumeButtonSubscription?.cancel();
        _positionStream?.cancel();
        break;
      default:
    }
  }

  void _getValuesFromDisk() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _correction = prefs.getDouble(correctionKey);
      _globalCounter = prefs.getDouble(globalCounterKey);
      if (_correction == null) {
        _correction = 1;
      }
      if (_globalCounter == null) {
        _globalCounter = 0;
      }
    });
  }

  void _storeValuesOnDisk() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setDouble(correctionKey, _correction);
    prefs.setDouble(globalCounterKey, _globalCounter);
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

  void showCorrectionOptions() {
    showDialog<Correction>(
        context: context,
        builder: (BuildContext context) {
          return SimpleDialog(
            title: const Text('Sélectionner la correction de distance'),
            children: Correction.values
                .map((correction) => SimpleDialogOption(
                      child: Text(
                        correctionName(correction),
                        style: TextStyle(
                            fontWeight:
                                correctionValue(correction) == _correction
                                    ? FontWeight.w900
                                    : FontWeight.normal),
                      ),
                      onPressed: () {
                        _correction = correctionValue(correction);
                        _storeValuesOnDisk();
                        Navigator.pop(context);
                      },
                    ))
                .toList(),
          );
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
          style: Theme.of(context).textTheme.display2,
        )),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: <Widget>[
                IconButton(
                  icon: Icon(Icons.remove),
                  iconSize: 96,
                  onPressed: () {
                    _decrementCounter(10);
                  },
                ),
                IconButton(
                  icon: Icon(Icons.add),
                  iconSize: 96,
                  onPressed: () {
                    _incrementCounter(10);
                  },
                ),
              ],
            ),
            GestureDetector(
              onLongPress: () {
                setState(() {
                  _stepCounter = 0;
                });
              },
              child: Text(
                '${(_stepCounter / 1000).toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.display4,
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
                style: Theme.of(context).textTheme.display4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum Correction {
  c80,
  c85,
  c90,
  c95,
  c100,
  c105,
  c110,
  c115,
  c120,
}

String correctionName(Correction correction) {
  switch (correction) {
    case Correction.c80:
      return "80%";
    case Correction.c85:
      return "85%";
    case Correction.c90:
      return "90%";
    case Correction.c95:
      return "95%";
    case Correction.c100:
      return "100%";
    case Correction.c105:
      return "105%";
    case Correction.c110:
      return "110%";
    case Correction.c115:
      return "115%";
    case Correction.c120:
      return "120%";
  }
}

double correctionValue(Correction correction) {
  switch (correction) {
    case Correction.c80:
      return 0.80;
    case Correction.c85:
      return 0.85;
    case Correction.c90:
      return 0.90;
    case Correction.c95:
      return 0.95;
    case Correction.c100:
      return 1.00;
    case Correction.c105:
      return 1.05;
    case Correction.c110:
      return 1.10;
    case Correction.c115:
      return 1.15;
    case Correction.c120:
      return 1.20;
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
