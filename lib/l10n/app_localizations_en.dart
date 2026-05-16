// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Inteshar Point';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navHierarchy => 'Hierarchy';

  @override
  String get navChildren => 'Children';

  @override
  String get navCatalog => 'Catalog';

  @override
  String get navInventory => 'Inventory';

  @override
  String get navBatchAdd => 'Batch Add';

  @override
  String get navTransactions => 'Transactions';

  @override
  String get navPos => 'POS';

  @override
  String get loginTitle => 'Sign In';

  @override
  String get loginPhone => 'Phone number';

  @override
  String get loginPassword => 'Password';

  @override
  String get loginSignIn => 'Sign in';

  @override
  String get loginServerUrl => 'Server URL';

  @override
  String get loginNoUsers =>
      'The backend has no users yet. Run the Mongo seed snippet from instructions.md §7 to create the first admin.';

  @override
  String get loginSeedDemo => 'Seed demo data';

  @override
  String get posHome => 'POS Home';

  @override
  String get posPrintVoucher => 'Print voucher';

  @override
  String get posConnectPrinter => 'Connect printer';

  @override
  String get posPrinterConnected => 'Printer connected';

  @override
  String posAvailable(int count) {
    return '$count available';
  }

  @override
  String get posSerial => 'Serial';

  @override
  String get posPin => 'PIN';

  @override
  String get signOut => 'Sign out';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutVersion => 'Version 1.0.0';

  @override
  String get aboutSupportedPrinters => 'Supported printers';

  @override
  String get aboutPrinterNote =>
      'All models print 58 mm ESC/POS via Bluetooth.';

  @override
  String get retryButton => 'Retry';

  @override
  String get emptyListHint => 'Nothing here yet.';
}
