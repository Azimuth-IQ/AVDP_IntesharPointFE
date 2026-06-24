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
  String get navTemplates => 'Templates';

  @override
  String get navMore => 'More';

  @override
  String get updateAvailableTitle => 'Update available';

  @override
  String get updateBody =>
      'A newer version of Inteshar Point is ready to install.';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredBody =>
      'A required update must be installed before you can continue.';

  @override
  String get updateWhatsNew => 'What\'s new';

  @override
  String get updateNow => 'Update now';

  @override
  String get updateLater => 'Later';

  @override
  String get updateDownloading => 'Downloading…';

  @override
  String get updateOpenInstaller => 'Opening installer…';

  @override
  String get updateRetry => 'Retry';

  @override
  String get updatePermissionBody =>
      'Enable “Install unknown apps” for Inteshar Point, then tap Update again.';

  @override
  String get updatePermissionOpenSettings => 'Open settings';

  @override
  String updateVersion(String version) {
    return 'Version $version';
  }

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
  String get posReveal => 'Reveal PIN';

  @override
  String get posRevealing => 'Revealing…';

  @override
  String get posRevealWarning =>
      'Revealing shows the code and marks this voucher as used — this can\'t be undone.';

  @override
  String get posPinHidden => 'Hidden until revealed';

  @override
  String get posDone => 'Done';

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

  @override
  String get languageLabel => 'Language';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get languageEnglish => 'English';

  @override
  String get commonClose => 'Close';

  @override
  String get commonSeedSuccess => 'Demo data seeded successfully!';

  @override
  String commonUpdateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String commonDeleteFailed(String error) {
    return 'Delete failed: $error';
  }

  @override
  String get loginWelcomeBack => 'Welcome back';

  @override
  String get loginSubtitle =>
      'Sign in to continue. Use the phone number and password issued by your administrator.';

  @override
  String get loginFieldRequired => 'Required';

  @override
  String get loginServerEndpoint => 'Server endpoint';

  @override
  String get loginBaseUrlLabel => 'Base URL';

  @override
  String get loginSaveEndpoint => 'Save endpoint';

  @override
  String get loginAuthDeclined => 'Authentication declined';

  @override
  String get loginNoUsersTitle => 'No users registered';

  @override
  String get loginNoUsersDefault =>
      'Default → phone 07701234567 · password \"password\"';

  @override
  String get loginBrandTagline =>
      'Press, charge, and go. Run the kingdom of vouchers from one fast counter.';

  @override
  String get loginBrandTaglineShort => 'Press, charge, and go.';

  @override
  String get splashTagline => 'Voucher distribution, made simple.';

  @override
  String get dashboardWelcomeBack => 'Welcome back,';

  @override
  String get dashboardQuickActions => 'Quick actions';

  @override
  String get dashboardOperatingNotes => 'Operating notes';

  @override
  String get dashboardChildrenNote => 'Direct downstream entities';

  @override
  String get dashboardProducts => 'Products';

  @override
  String get dashboardProductsNote => 'Tied to this entity';

  @override
  String get dashboardActionHierarchyDesc => 'Manage the chain of distribution';

  @override
  String get dashboardActionCatalogDesc => 'Define vouchers and prices';

  @override
  String get dashboardActionTemplatesDesc =>
      'Design the thermal receipt and QR for each product.';

  @override
  String get dashboardActionInventoryHqDesc => 'Browse the printed stock';

  @override
  String get dashboardActionBatchAddDesc => 'Mint a run of new vouchers';

  @override
  String get dashboardActionTransactionsDesc => 'Move stock between entities';

  @override
  String get dashboardActionChildrenAgent1Desc =>
      'Govern distributors and stores';

  @override
  String get dashboardActionInventoryAgentDesc => 'Inspect on-hand vouchers';

  @override
  String get dashboardActionTransactionsAgentDesc => 'Issue & receive stock';

  @override
  String get dashboardActionChildrenAgent2Desc => 'Manage assigned stores';

  @override
  String get dashboardActionInventoryStoreDesc => 'Counter stock at a glance';

  @override
  String get dashboardActionTransactionsStoreDesc =>
      'Receipts received from above';

  @override
  String get dashboardOpenPos => 'Open POS';

  @override
  String get dashboardActionOpenPosDesc => 'Print at the counter';

  @override
  String get dashboardNoteHq1 =>
      'Cut and dispatch fresh vouchers via Batch Add — the catalog drives every printed slip.';

  @override
  String get dashboardNoteHq2 =>
      'Hierarchy changes route stock; review the chain before issuing a transaction.';

  @override
  String get dashboardNoteHq3 =>
      'Long-press the brand mark to open backend diagnostics.';

  @override
  String get dashboardNoteAgent1 =>
      'Issue stock to your downstream children before they request it — print-on-demand fails when shelves are empty.';

  @override
  String get dashboardNoteAgent2 =>
      'Transactions poll every second on the server; allow up to thirty seconds to settle.';

  @override
  String get dashboardNoteStore1 =>
      'Open POS for counter operation. Each printed voucher is marked PRINTED on the server.';

  @override
  String get dashboardNoteStore2 =>
      'Status PRINTED can be reverted only by an administrator.';

  @override
  String get healthDiagnosticsTitle => 'Diagnostics';

  @override
  String get healthRefresh => 'Refresh';

  @override
  String get healthConnectionSection => 'Connection';

  @override
  String get healthBaseUrl => 'Base URL';

  @override
  String get healthJwt => 'JWT';

  @override
  String get healthChecksSection => 'Health checks';

  @override
  String get healthNoResults => 'No results yet.';

  @override
  String get healthFailed => 'Failed';

  @override
  String get entityTypeInteshar => 'Inteshar';

  @override
  String get entityTypeAgent1 => 'Main Agent';

  @override
  String get entityTypeAgent2 => 'Sub Agent';

  @override
  String get entityTypeStore => 'Store';

  @override
  String get entityTypeUser => 'User';

  @override
  String get entityTreeSubtitle =>
      'A breadth-first view of every entity beneath you.';

  @override
  String get entityTreeLevels => 'Levels';

  @override
  String get entityTreeEntities => 'Entities';

  @override
  String get entityTreeNoChildren => 'No children registered yet.';

  @override
  String get entityTreeRefresh => 'Refresh';

  @override
  String get entityTreeRoot => 'Root';

  @override
  String entityTreeLevel(String level) {
    return 'Level $level';
  }

  @override
  String entityTreeEntityCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entities',
      one: '1 entity',
    );
    return '$_temp0';
  }

  @override
  String entityTreeChildrenCount(int count) {
    return '$count children';
  }

  @override
  String entityTreeProductsCount(int count) {
    return '$count products';
  }

  @override
  String get entityTreeActions => 'Actions';

  @override
  String get entityTreeEdit => 'Edit';

  @override
  String get entityTreeManageUsers => 'Manage Users';

  @override
  String get entityTreeAddChild => 'Add Child';

  @override
  String get entityTreeDelete => 'Delete';

  @override
  String get entityTreeIdent => 'IDENT';

  @override
  String get entityTreeParentLabel => 'PARENT';

  @override
  String entityTreeAmendTitle(String typeName) {
    return 'Amend $typeName';
  }

  @override
  String entityTreeAddChildTitle(String typeName) {
    return 'Add $typeName';
  }

  @override
  String get entityTreeDeleteTitle => 'Delete entity';

  @override
  String entityTreeDeleteConfirm(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String get entityTreeCancel => 'Cancel';

  @override
  String get entityTreeDeleteFailed => 'Delete failed. Please try again.';

  @override
  String get entityTreeSectionLabel => 'Hierarchy edit';

  @override
  String get entityTreeFieldName => 'Name *';

  @override
  String get entityTreeFieldSlogan => 'Slogan';

  @override
  String get entityTreeFieldDescription => 'Description';

  @override
  String get entityTreeSave => 'Save';

  @override
  String get entityTreeErrorSaving => 'An error occurred while saving.';

  @override
  String get entityTreeColEntity => 'ENTITY';

  @override
  String get entityTreeColChildren => 'CHILDREN';

  @override
  String get entityTreeColVouchers => 'VOUCHERS';

  @override
  String get entityFieldLogoUrl => 'Logo URL';

  @override
  String get entityFieldPrimaryColor => 'Primary colour (hex)';

  @override
  String get entityFieldSecondaryColor => 'Accent colour (hex)';

  @override
  String get entityFieldLowStockThreshold => 'Low-stock alert level';

  @override
  String get entityFieldLowStockThresholdHelp =>
      'Flag a SKU as low when its available units fall below this. Leave empty for the default.';

  @override
  String get manageUsersSectionLabel => 'User register';

  @override
  String get manageUsersTitle => 'Manage users';

  @override
  String get manageUsersEmpty => 'No users on file. Register one below.';

  @override
  String get manageUsersNewUser => 'NEW USER';

  @override
  String get manageUsersPhone => 'Phone *';

  @override
  String get manageUsersPassword => 'Password *';

  @override
  String get manageUsersRole => 'Role';

  @override
  String get manageUsersRegisterButton => 'Register user';

  @override
  String get manageUsersSave => 'Save register';

  @override
  String get manageUsersPhoneRequired => 'Phone is required';

  @override
  String get manageUsersPasswordRequired => 'Password is required';

  @override
  String get manageUsersPhoneDuplicate =>
      'A user with this phone already exists';

  @override
  String get manageUsersAtLeastOne => 'At least one user is required';

  @override
  String get manageUsersErrorSaving => 'An error occurred while saving.';

  @override
  String get batchAddEyebrow => 'Stock';

  @override
  String get batchAddTitle => 'Add vouchers';

  @override
  String get batchAddSubtitle =>
      'Add a single voucher by hand, or import a batch from an XLSX manifest.';

  @override
  String get batchAddTabSingle => 'Single';

  @override
  String get batchAddTabCsvXlsx => 'CSV / XLSX';

  @override
  String get batchAddDenomination => 'Denomination';

  @override
  String get batchAddProductDefinition => 'Product definition';

  @override
  String batchAddImportedProducts(int count) {
    return 'Imported $count products!';
  }

  @override
  String get batchAddCsvFormat => 'Manifest format';

  @override
  String get batchAddRequiredColumns => 'Required columns';

  @override
  String get batchAddDownloadTemplate => 'Download XLSX template';

  @override
  String get batchAddTemplateSaved => 'Template saved.';

  @override
  String get batchAddPickFile => 'Pick CSV / XLSX file';

  @override
  String get batchAddErrorReadBytes => 'Could not read file bytes.';

  @override
  String get batchAddXlsxBadHeader =>
      'XLSX must have \'serialNumber\' and \'pin\' header columns.';

  @override
  String batchAddDuplicateRow(int index, String serial) {
    return 'Row $index: serial \'$serial\' already exists in this entity\'s inventory.';
  }

  @override
  String get batchAddPreview => 'Preview';

  @override
  String batchAddRowCount(int count) {
    return '$count rows';
  }

  @override
  String get batchAddColSerial => 'SERIAL';

  @override
  String get batchAddColPin => 'PIN';

  @override
  String batchAddMoreRows(int count) {
    return '+ $count more rows';
  }

  @override
  String batchAddProgressImported(int done, int total) {
    return '$done / $total imported';
  }

  @override
  String batchAddImportRows(int count) {
    return 'Import $count rows';
  }

  @override
  String batchAddFailedAtRow(int index, String error) {
    return 'Failed at row $index: $error';
  }

  @override
  String get batchAddPrinting => 'PRINTING';

  @override
  String get addVoucherDenomination => 'Denomination';

  @override
  String get addVoucherSerial => 'Serial number';

  @override
  String get addVoucherPin => 'PIN';

  @override
  String get addVoucherSave => 'Save voucher';

  @override
  String get addVoucherSerialRequired => 'Serial number is required';

  @override
  String get addVoucherPinRequired => 'PIN is required';

  @override
  String addVoucherDuplicateSerial(String serial) {
    return 'Serial \'$serial\' already exists in this entity\'s inventory.';
  }

  @override
  String get addVoucherSaved => 'Voucher saved.';

  @override
  String get defsFormTitleNew => 'New Definition';

  @override
  String get defsFormTitleEdit => 'Edit Definition';

  @override
  String get defsDeleteTitle => 'Delete definition';

  @override
  String defsDeleteConfirm(String name) {
    return 'Delete \"$name\"? This may break existing products.';
  }

  @override
  String get defsCancel => 'Cancel';

  @override
  String get defsDelete => 'Delete';

  @override
  String get defsSubtitle =>
      'Master record of voucher denominations issued by Inteshar Store.';

  @override
  String get defsTitlesLabel => 'titles';

  @override
  String get defsSearchHint => 'Search by name, SKU, or description…';

  @override
  String get defsEmptyFirst =>
      'No product definitions yet. Mint the first denomination.';

  @override
  String defsEmptySearch(String query) {
    return 'Nothing matches \"$query\".';
  }

  @override
  String get defsAddFirst => 'Add first';

  @override
  String get defsNewDenomination => 'New denomination';

  @override
  String get defsPrice => 'Price';

  @override
  String get defsEdit => 'Edit';

  @override
  String get defsMintLabel => 'Mint a denomination';

  @override
  String get defsAmendLabel => 'Amend a denomination';

  @override
  String get defsFieldName => 'Name *';

  @override
  String get defsFieldSku => 'SKU * (e.g. AC5)';

  @override
  String get defsFieldPrice => 'Default Price (IQD) *';

  @override
  String get defsFieldDescription => 'Description';

  @override
  String get defsFieldId => 'ID (auto-generated)';

  @override
  String get defsSave => 'Save';

  @override
  String get inventoryEyebrow => 'The Counter';

  @override
  String get inventorySubtitle =>
      'Vouchers currently owned by this entity — search by name, SKU, or serial.';

  @override
  String get inventoryStatusAvailable => 'Available';

  @override
  String get inventoryStatusPrinted => 'Used';

  @override
  String get inventoryStatusDamaged => 'Damaged';

  @override
  String get inventoryStatusSentForPrinting => 'Sent for printing';

  @override
  String get inventoryStatusFailedPrinting => 'Print failed';

  @override
  String get inventorySearchHint => 'Search by name, SKU, or serial…';

  @override
  String get inventoryFilterAll => 'All';

  @override
  String get inventoryEmptyFirst => 'No products held by this entity yet.';

  @override
  String get inventoryEmptyFiltered => 'No products match the current filters.';

  @override
  String get inventoryRefresh => 'Refresh';

  @override
  String inventoryUnitCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count units',
      one: '1 unit',
    );
    return '$_temp0';
  }

  @override
  String inventoryAvailableCount(int count) {
    return '$count available';
  }

  @override
  String inventoryPrintedCount(int count) {
    return '$count used';
  }

  @override
  String inventoryDamagedCount(int count) {
    return '$count damaged';
  }

  @override
  String get inventorySnLabel => 'SN';

  @override
  String get inventoryChangeStatus => 'Change status';

  @override
  String inventoryMarkStatus(String status) {
    return 'Mark $status';
  }

  @override
  String get inventoryValueLabel => 'Inventory value';

  @override
  String get inventoryValueUnits => 'available units';

  @override
  String get inventoryLoadMore => 'Load more';

  @override
  String inventoryShowingCount(int shown, int total) {
    return 'Showing $shown of $total';
  }

  @override
  String get inventoryNoCodes => 'No codes to show.';

  @override
  String get inventoryLoadCodesFailed => 'Couldn\'t load codes.';

  @override
  String get posHomeLiveCounter => 'Live counter';

  @override
  String get posHomeSetupPrinter => 'Setup printer';

  @override
  String get posHomePickDenomination => 'Pick a denomination';

  @override
  String get posHomeCounterSubtitle =>
      'Print at the counter from available stock.';

  @override
  String get posHomeSearchHint => 'Search by name or SKU…';

  @override
  String get posHomeInStock => 'IN STOCK';

  @override
  String get posHomeNoVouchers => 'No available vouchers on the counter.';

  @override
  String posHomeNoMatches(String query) {
    return 'Nothing matches \"$query\".';
  }

  @override
  String get posHomePrint => 'Print';

  @override
  String get posHomeScratchNote => 'Scratch only at point of redemption.';

  @override
  String get posHomePrinterNotConnected => 'Printer not connected';

  @override
  String get posHomeCancel => 'Cancel';

  @override
  String get posHomePrinting => 'Printing…';

  @override
  String posHomeUpdateError(String error) {
    return 'Could not update status: $error';
  }

  @override
  String posHomePrintFailed(String error) {
    return 'Print failed: $error';
  }

  @override
  String get printerPickerTitle => 'Printer setup';

  @override
  String get printerPickerConnectedManual => 'Connected via manual address';

  @override
  String printerPickerConnectionFailed(String error) {
    return 'Connection failed: $error';
  }

  @override
  String printerPickerConnectedTo(String name) {
    return 'Connected to $name';
  }

  @override
  String get printerPickerTestPrintSent => 'Test print sent!';

  @override
  String printerPickerPrintError(String error) {
    return 'Print error: $error';
  }

  @override
  String get printerPickerConnected => 'CONNECTED';

  @override
  String get printerPickerTestPrint => 'Test print';

  @override
  String get printerPickerDisconnect => 'Disconnect';

  @override
  String get printerPickerManualAddress => 'Manual address';

  @override
  String get printerPickerManualHint =>
      'Use this when the device is not visible in the scan list.';

  @override
  String get printerPickerEnterMac => 'Enter a MAC address';

  @override
  String get printerPickerMacFormat => 'Format: XX:XX:XX:XX:XX:XX';

  @override
  String get printerPickerMacLabel => 'Bluetooth MAC address';

  @override
  String get printerPickerPair => 'Pair';

  @override
  String get printerPickerNearbyDevices => 'Nearby devices';

  @override
  String get printerPickerRescan => 'Re-scan';

  @override
  String get printerPickerNoDevices =>
      'No devices found. Make sure Bluetooth is on and the printer is powered.';

  @override
  String get printerPickerUnknown => 'Unknown';

  @override
  String get newTxnTitle => 'New transaction';

  @override
  String get newTxnIssueStock => 'Issue stock';

  @override
  String get newTxnIssueStockHint =>
      'Pick a destination, list the denominations, and submit. The server polls every second; allow up to 30 seconds for the ledger to settle.';

  @override
  String get newTxnManifestLines => 'Manifest lines';

  @override
  String get newTxnAddLine => 'Add line';

  @override
  String get newTxnGrandTotal => 'Grand total';

  @override
  String newTxnUnitsCount(int count) {
    return '$count units';
  }

  @override
  String get newTxnSource => 'Source';

  @override
  String get newTxnDestination => 'Destination';

  @override
  String get newTxnNoChildren => 'No downstream children';

  @override
  String get newTxnNoChildrenHint => 'Add a child via the hierarchy first';

  @override
  String get newTxnChooseEntity => 'Choose entity';

  @override
  String get newTxnProduct => 'Product';

  @override
  String get newTxnQty => 'Qty';

  @override
  String get newTxnUnitPrice => 'Unit price (IQD)';

  @override
  String get newTxnLineTotal => 'Line total';

  @override
  String get newTxnPosting => 'Posting…';

  @override
  String get newTxnSubmit => 'Submit transaction';

  @override
  String get newTxnPostedToLedger => 'Posted to ledger';

  @override
  String get newTxnDeclined => 'Transaction declined';

  @override
  String get newTxnResultPosted => 'posted';

  @override
  String get newTxnResultDeclined => 'declined';

  @override
  String newTxnRef(String id) {
    return 'Ref · $id';
  }

  @override
  String get newTxnReturnToTransactions => 'Return to transactions';

  @override
  String get txnsSubtitle =>
      'Movements of stock to and from this entity, latest first.';

  @override
  String get txnsTallyOut => 'out';

  @override
  String get txnsTallyIn => 'in';

  @override
  String get txnsTallyDone => 'done';

  @override
  String get txnsEmpty => 'No transactions on the ledger yet for this entity.';

  @override
  String get txnsCreateAction => 'Create transaction';

  @override
  String get txnsDirectionTo => 'To';

  @override
  String get txnsDirectionFrom => 'From';

  @override
  String txnsUnitLineSummary(int units, int lines) {
    String _temp0 = intl.Intl.pluralLogic(
      units,
      locale: localeName,
      other: 'units',
      one: 'unit',
    );
    String _temp1 = intl.Intl.pluralLogic(
      lines,
      locale: localeName,
      other: 'lines',
      one: 'line',
    );
    return '$units $_temp0 · $lines $_temp1';
  }

  @override
  String get txnsViewDetails => 'View details';

  @override
  String get txnsDetailTitle => 'Transaction details';

  @override
  String get txnsFrom => 'FROM';

  @override
  String get txnsTo => 'TO';

  @override
  String get txnsMetaReference => 'Reference';

  @override
  String get txnsMetaIssued => 'Issued';

  @override
  String get txnsMetaNote => 'Note';

  @override
  String get txnsLineItems => 'Line items';

  @override
  String get txnsColSku => 'SKU';

  @override
  String get txnsColQty => 'QTY';

  @override
  String get txnsColUnit => 'UNIT';

  @override
  String get txnsColTotal => 'TOTAL';

  @override
  String get txnStatusPending => 'Pending';

  @override
  String get txnStatusProcessing => 'Processing';

  @override
  String get txnStatusComplete => 'Completed';

  @override
  String get txnStatusFailed => 'Failed';

  @override
  String get appShellActiveEntity => 'Active entity';

  @override
  String get emptyStateTitle => 'Nothing here yet';

  @override
  String get errorStateErrorLabel => 'Error';

  @override
  String get errorStateTitle => 'Something interrupted this request.';

  @override
  String get vtTitle => 'Voucher Templates';

  @override
  String get vtSubtitle =>
      'Design the printed voucher for each product — header, fields, and a scannable QR.';

  @override
  String get vtSelectPrompt => 'Select a product to edit its template';

  @override
  String get vtHeaderText => 'Header text';

  @override
  String get vtFields => 'Fields';

  @override
  String get vtShowProductName => 'Show product name';

  @override
  String get vtShowSerial => 'Show serial number';

  @override
  String get vtShowPin => 'Show PIN';

  @override
  String get vtShowPrice => 'Show price';

  @override
  String get vtQrSection => 'QR code';

  @override
  String get vtQrEnabled => 'Enable QR';

  @override
  String get vtQrSource => 'QR encodes';

  @override
  String get vtQrSourcePin => 'PIN';

  @override
  String get vtQrSourceSerial => 'Serial';

  @override
  String get vtQrPrefix => 'QR prefix';

  @override
  String get vtQrSuffix => 'QR suffix';

  @override
  String get vtQrExample => 'Scans as';

  @override
  String get vtRedeemInstructions => 'Redeem instructions';

  @override
  String get vtFooterText => 'Footer text';

  @override
  String get vtPreview => 'Live preview';

  @override
  String get vtSave => 'Save template';

  @override
  String get vtSaved => 'Template saved';

  @override
  String get vtSaveFailed => 'Could not save template';

  @override
  String get vtEmpty => 'No products yet — create one in the Catalog first.';

  @override
  String get dashKpiStock => 'Vouchers in stock';

  @override
  String get dashKpiTransactions => 'Transactions';

  @override
  String get dashKpiLowStock => 'Low-stock SKUs';

  @override
  String get dashPlatformOverview => 'Platform overview';

  @override
  String get dashKpiDirectChildren => 'direct children';

  @override
  String dashKpiSkusCount(int count) {
    return '$count SKUs';
  }

  @override
  String get dashKpiThisAccount => 'this account';

  @override
  String get dashKpiAllHealthy => 'all healthy';

  @override
  String get dashKpiNeedsAttention => 'needs attention';

  @override
  String get dashRecentTransactions => 'Recent transactions';

  @override
  String get dashLowStock => 'Low stock';

  @override
  String get dashViewAll => 'View all';

  @override
  String get dashColRoute => 'Route';

  @override
  String get dashColSku => 'SKU';

  @override
  String get dashColQty => 'Qty';

  @override
  String get dashColStatus => 'Status';

  @override
  String get dashColAmount => 'Amount';

  @override
  String get dashUnitsLeft => 'left';

  @override
  String get dashAllHealthy => 'All stock levels healthy';

  @override
  String get dashNoTransactions => 'No transactions yet';

  @override
  String get navSystemActivity => 'System Activity';

  @override
  String get sysActSubtitle =>
      'A live operational feed across the platform — events, transactions, entities and users.';

  @override
  String get sysActActivity => 'Activity';

  @override
  String get sysActEntities => 'Entities';

  @override
  String get sysActUsers => 'Users';

  @override
  String get sysActStores => 'Stores';

  @override
  String get sysActFailed => 'Failed';

  @override
  String get sysActLevelInfo => 'Info';

  @override
  String get sysActLevelWarn => 'Warnings';

  @override
  String get sysActLevelError => 'Errors';

  @override
  String get sysActFailuresOnly => 'Failures only';

  @override
  String get sysActSearchPath => 'Filter by path…';

  @override
  String get sysActSearchEntities => 'Search entities…';

  @override
  String get sysActSearchUsers => 'Search by phone…';

  @override
  String get sysActNoEvents => 'No activity events match these filters.';

  @override
  String get sysActNoEntities => 'No entities found.';

  @override
  String get sysActNoUsers => 'No users found.';

  @override
  String get sysActAdminOnly =>
      'Couldn\'t authorize this request. Your session may have expired, or this account lacks administrator access.';

  @override
  String get sysActReauth => 'Sign in again';

  @override
  String sysActUsersCount(int count) {
    return '$count users';
  }

  @override
  String get sysActRoleAdmin => 'Admin';

  @override
  String get sysActSourceServer => 'Server';

  @override
  String get sysActSourceClient => 'Client';

  @override
  String get sysActDetailTitle => 'Event details';

  @override
  String get sysActFieldTime => 'Time';

  @override
  String get sysActFieldSource => 'Source';

  @override
  String get sysActFieldLevel => 'Level';

  @override
  String get sysActFieldMethod => 'Method';

  @override
  String get sysActFieldPath => 'Path';

  @override
  String get sysActFieldAction => 'Action';

  @override
  String get sysActFieldUser => 'User';

  @override
  String get sysActFieldEntity => 'Entity';

  @override
  String get sysActFieldPlatform => 'Platform';

  @override
  String get sysActFieldSurface => 'Surface';

  @override
  String get sysActFieldDevice => 'Device';

  @override
  String get sysActFieldAppVersion => 'App version';

  @override
  String get sysActFieldDuration => 'Duration';

  @override
  String get sysActFieldIp => 'IP address';

  @override
  String get sysActFieldCorrelation => 'Correlation ID';

  @override
  String get sysActFieldError => 'Error';

  @override
  String get sysActFieldStack => 'Stack trace';

  @override
  String sysActDurationMs(int ms) {
    return '$ms ms';
  }

  @override
  String get navMainAgents => 'Main Agents';

  @override
  String get navSubAgents => 'Sub Agents';

  @override
  String get navCompanies => 'Companies';

  @override
  String get navPrices => 'Prices';

  @override
  String get batchAddGovernorate => 'Governorate (region lock)';

  @override
  String get batchAddNotGeoLocked => 'Not region-locked';

  @override
  String get newTxnNoRegionRestriction => 'no region restriction';

  @override
  String newTxnDeliverableHint(String coverage) {
    return 'Only vouchers for $coverage (plus non-region-locked stock) will be delivered.';
  }
}
