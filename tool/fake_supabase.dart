// A tiny local stand-in for a Supabase project, for trying sync on real devices.
//
//   dart run tool/fake_supabase.dart            (listens on port 54321)
//
// It speaks just enough of Supabase's web API for Bayar: sign-in, sign-up, and
// the data tables, with per-user isolation and server timestamps. It keeps
// everything in memory, so stopping it forgets all data. For testing only.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../test/support/fake_supabase_http.dart';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args.first) : 54321;
  final fake = FakeSupabaseServer()..users['me@example.com'] = 'secret1';
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('Fake Supabase on http://0.0.0.0:$port  (account: me@example.com / secret1)');

  await for (final request in server) {
    final body = await utf8.decoder.bind(request).join();
    final forwarded = http.Request(request.method, request.requestedUri)
      ..body = body
      ..headers.addAll({
        for (final name in ['authorization', 'apikey', 'prefer', 'content-type'])
          if (request.headers.value(name) != null) name: request.headers.value(name)!,
      });
    final response = await fake.handle(forwarded);
    request.response
      ..statusCode = response.statusCode
      ..headers.contentType = ContentType.json
      ..write(response.body);
    await request.response.close();
    stdout.writeln('${request.method} ${request.uri.path} -> ${response.statusCode}');
  }
}
