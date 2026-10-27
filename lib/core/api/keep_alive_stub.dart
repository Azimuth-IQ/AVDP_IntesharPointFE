import 'package:dio/dio.dart';

/// No-op on web: the browser keeps and reuses its own connections.
void keepConnectionsAlive(Dio dio) {}
