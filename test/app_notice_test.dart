import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_mobile/core/app_notice.dart';

void main() {
  testWidgets('shows notices at the top and replaces the previous notice',
      (tester) async {
    late BuildContext pageContext;
    addTearDown(AppNotice.dismiss);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              pageContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    AppNotice.show(
      pageContext,
      const SnackBar(
        content: Text('Pembayaran berhasil'),
        duration: Duration(hours: 1),
      ),
    );
    await tester.pump();

    final noticeRect = tester.getRect(find.text('Pembayaran berhasil'));
    final screenHeight = tester.getRect(find.byType(Scaffold)).height;
    expect(noticeRect.top, lessThan(screenHeight / 2));

    AppNotice.show(
      pageContext,
      const SnackBar(
        content: Text('Sinkronisasi selesai'),
        duration: Duration(hours: 1),
      ),
    );
    await tester.pump();

    expect(find.text('Pembayaran berhasil'), findsNothing);
    expect(find.text('Sinkronisasi selesai'), findsOneWidget);

    AppNotice.dismiss();
    await tester.pump();
  });
}
