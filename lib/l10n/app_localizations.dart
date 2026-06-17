import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Inteshar Point'**
  String get appTitle;

  /// No description provided for @navDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// No description provided for @navHierarchy.
  ///
  /// In en, this message translates to:
  /// **'Hierarchy'**
  String get navHierarchy;

  /// No description provided for @navChildren.
  ///
  /// In en, this message translates to:
  /// **'Children'**
  String get navChildren;

  /// No description provided for @navCatalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get navCatalog;

  /// No description provided for @navInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get navInventory;

  /// No description provided for @navBatchAdd.
  ///
  /// In en, this message translates to:
  /// **'Batch Add'**
  String get navBatchAdd;

  /// No description provided for @navTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get navTransactions;

  /// No description provided for @navPos.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get navPos;

  /// No description provided for @navTemplates.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get navTemplates;

  /// Mobile bottom-nav overflow tab opening the secondary destinations sheet
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @loginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get loginTitle;

  /// No description provided for @loginPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get loginPhone;

  /// No description provided for @loginPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get loginPassword;

  /// No description provided for @loginSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get loginSignIn;

  /// No description provided for @loginServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get loginServerUrl;

  /// No description provided for @loginNoUsers.
  ///
  /// In en, this message translates to:
  /// **'The backend has no users yet. Run the Mongo seed snippet from instructions.md §7 to create the first admin.'**
  String get loginNoUsers;

  /// No description provided for @loginSeedDemo.
  ///
  /// In en, this message translates to:
  /// **'Seed demo data'**
  String get loginSeedDemo;

  /// No description provided for @posHome.
  ///
  /// In en, this message translates to:
  /// **'POS Home'**
  String get posHome;

  /// No description provided for @posPrintVoucher.
  ///
  /// In en, this message translates to:
  /// **'Print voucher'**
  String get posPrintVoucher;

  /// No description provided for @posConnectPrinter.
  ///
  /// In en, this message translates to:
  /// **'Connect printer'**
  String get posConnectPrinter;

  /// No description provided for @posPrinterConnected.
  ///
  /// In en, this message translates to:
  /// **'Printer connected'**
  String get posPrinterConnected;

  /// No description provided for @posAvailable.
  ///
  /// In en, this message translates to:
  /// **'{count} available'**
  String posAvailable(int count);

  /// No description provided for @posSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial'**
  String get posSerial;

  /// No description provided for @posPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get posPin;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutTitle;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0.0'**
  String get aboutVersion;

  /// No description provided for @aboutSupportedPrinters.
  ///
  /// In en, this message translates to:
  /// **'Supported printers'**
  String get aboutSupportedPrinters;

  /// No description provided for @aboutPrinterNote.
  ///
  /// In en, this message translates to:
  /// **'All models print 58 mm ESC/POS via Bluetooth.'**
  String get aboutPrinterNote;

  /// No description provided for @retryButton.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// No description provided for @emptyListHint.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet.'**
  String get emptyListHint;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonSeedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Demo data seeded successfully!'**
  String get commonSeedSuccess;

  /// No description provided for @commonUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String commonUpdateFailed(String error);

  /// No description provided for @commonDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed: {error}'**
  String commonDeleteFailed(String error);

  /// No description provided for @loginWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get loginWelcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue. Use the phone number and password issued by your administrator.'**
  String get loginSubtitle;

  /// No description provided for @loginFieldRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get loginFieldRequired;

  /// No description provided for @loginServerEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Server endpoint'**
  String get loginServerEndpoint;

  /// No description provided for @loginBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get loginBaseUrlLabel;

  /// No description provided for @loginSaveEndpoint.
  ///
  /// In en, this message translates to:
  /// **'Save endpoint'**
  String get loginSaveEndpoint;

  /// No description provided for @loginAuthDeclined.
  ///
  /// In en, this message translates to:
  /// **'Authentication declined'**
  String get loginAuthDeclined;

  /// No description provided for @loginNoUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'No users registered'**
  String get loginNoUsersTitle;

  /// No description provided for @loginNoUsersDefault.
  ///
  /// In en, this message translates to:
  /// **'Default → phone 07701234567 · password \"password\"'**
  String get loginNoUsersDefault;

  /// No description provided for @loginBrandTagline.
  ///
  /// In en, this message translates to:
  /// **'Press, charge, and go. Run the kingdom of vouchers from one fast counter.'**
  String get loginBrandTagline;

  /// No description provided for @loginBrandTaglineShort.
  ///
  /// In en, this message translates to:
  /// **'Press, charge, and go.'**
  String get loginBrandTaglineShort;

  /// No description provided for @splashTagline.
  ///
  /// In en, this message translates to:
  /// **'Voucher distribution, made simple.'**
  String get splashTagline;

  /// No description provided for @dashboardWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get dashboardWelcomeBack;

  /// No description provided for @dashboardQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get dashboardQuickActions;

  /// No description provided for @dashboardOperatingNotes.
  ///
  /// In en, this message translates to:
  /// **'Operating notes'**
  String get dashboardOperatingNotes;

  /// No description provided for @dashboardChildrenNote.
  ///
  /// In en, this message translates to:
  /// **'Direct downstream entities'**
  String get dashboardChildrenNote;

  /// No description provided for @dashboardProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get dashboardProducts;

  /// No description provided for @dashboardProductsNote.
  ///
  /// In en, this message translates to:
  /// **'Tied to this entity'**
  String get dashboardProductsNote;

  /// No description provided for @dashboardActionHierarchyDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage the chain of distribution'**
  String get dashboardActionHierarchyDesc;

  /// No description provided for @dashboardActionCatalogDesc.
  ///
  /// In en, this message translates to:
  /// **'Define vouchers and prices'**
  String get dashboardActionCatalogDesc;

  /// No description provided for @dashboardActionTemplatesDesc.
  ///
  /// In en, this message translates to:
  /// **'Design the thermal receipt and QR for each product.'**
  String get dashboardActionTemplatesDesc;

  /// No description provided for @dashboardActionInventoryHqDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse the printed stock'**
  String get dashboardActionInventoryHqDesc;

  /// No description provided for @dashboardActionBatchAddDesc.
  ///
  /// In en, this message translates to:
  /// **'Mint a run of new vouchers'**
  String get dashboardActionBatchAddDesc;

  /// No description provided for @dashboardActionTransactionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Move stock between entities'**
  String get dashboardActionTransactionsDesc;

  /// No description provided for @dashboardActionChildrenAgent1Desc.
  ///
  /// In en, this message translates to:
  /// **'Govern distributors and stores'**
  String get dashboardActionChildrenAgent1Desc;

  /// No description provided for @dashboardActionInventoryAgentDesc.
  ///
  /// In en, this message translates to:
  /// **'Inspect on-hand vouchers'**
  String get dashboardActionInventoryAgentDesc;

  /// No description provided for @dashboardActionTransactionsAgentDesc.
  ///
  /// In en, this message translates to:
  /// **'Issue & receive stock'**
  String get dashboardActionTransactionsAgentDesc;

  /// No description provided for @dashboardActionChildrenAgent2Desc.
  ///
  /// In en, this message translates to:
  /// **'Manage assigned stores'**
  String get dashboardActionChildrenAgent2Desc;

  /// No description provided for @dashboardActionInventoryStoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Counter stock at a glance'**
  String get dashboardActionInventoryStoreDesc;

  /// No description provided for @dashboardActionTransactionsStoreDesc.
  ///
  /// In en, this message translates to:
  /// **'Receipts received from above'**
  String get dashboardActionTransactionsStoreDesc;

  /// No description provided for @dashboardOpenPos.
  ///
  /// In en, this message translates to:
  /// **'Open POS'**
  String get dashboardOpenPos;

  /// No description provided for @dashboardActionOpenPosDesc.
  ///
  /// In en, this message translates to:
  /// **'Print at the counter'**
  String get dashboardActionOpenPosDesc;

  /// No description provided for @dashboardNoteHq1.
  ///
  /// In en, this message translates to:
  /// **'Cut and dispatch fresh vouchers via Batch Add — the catalog drives every printed slip.'**
  String get dashboardNoteHq1;

  /// No description provided for @dashboardNoteHq2.
  ///
  /// In en, this message translates to:
  /// **'Hierarchy changes route stock; review the chain before issuing a transaction.'**
  String get dashboardNoteHq2;

  /// No description provided for @dashboardNoteHq3.
  ///
  /// In en, this message translates to:
  /// **'Long-press the brand mark to open backend diagnostics.'**
  String get dashboardNoteHq3;

  /// No description provided for @dashboardNoteAgent1.
  ///
  /// In en, this message translates to:
  /// **'Issue stock to your downstream children before they request it — print-on-demand fails when shelves are empty.'**
  String get dashboardNoteAgent1;

  /// No description provided for @dashboardNoteAgent2.
  ///
  /// In en, this message translates to:
  /// **'Transactions poll every second on the server; allow up to thirty seconds to settle.'**
  String get dashboardNoteAgent2;

  /// No description provided for @dashboardNoteStore1.
  ///
  /// In en, this message translates to:
  /// **'Open POS for counter operation. Each printed voucher is marked PRINTED on the server.'**
  String get dashboardNoteStore1;

  /// No description provided for @dashboardNoteStore2.
  ///
  /// In en, this message translates to:
  /// **'Status PRINTED can be reverted only by an administrator.'**
  String get dashboardNoteStore2;

  /// No description provided for @healthDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get healthDiagnosticsTitle;

  /// No description provided for @healthRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get healthRefresh;

  /// No description provided for @healthConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get healthConnectionSection;

  /// No description provided for @healthBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get healthBaseUrl;

  /// No description provided for @healthJwt.
  ///
  /// In en, this message translates to:
  /// **'JWT'**
  String get healthJwt;

  /// No description provided for @healthChecksSection.
  ///
  /// In en, this message translates to:
  /// **'Health checks'**
  String get healthChecksSection;

  /// No description provided for @healthNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results yet.'**
  String get healthNoResults;

  /// No description provided for @healthFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get healthFailed;

  /// No description provided for @entityTypeInteshar.
  ///
  /// In en, this message translates to:
  /// **'Inteshar'**
  String get entityTypeInteshar;

  /// No description provided for @entityTypeAgent1.
  ///
  /// In en, this message translates to:
  /// **'Agent 1'**
  String get entityTypeAgent1;

  /// No description provided for @entityTypeAgent2.
  ///
  /// In en, this message translates to:
  /// **'Agent 2'**
  String get entityTypeAgent2;

  /// No description provided for @entityTypeStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get entityTypeStore;

  /// No description provided for @entityTypeUser.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get entityTypeUser;

  /// No description provided for @entityTreeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A breadth-first view of every entity beneath you.'**
  String get entityTreeSubtitle;

  /// No description provided for @entityTreeLevels.
  ///
  /// In en, this message translates to:
  /// **'Levels'**
  String get entityTreeLevels;

  /// No description provided for @entityTreeEntities.
  ///
  /// In en, this message translates to:
  /// **'Entities'**
  String get entityTreeEntities;

  /// No description provided for @entityTreeNoChildren.
  ///
  /// In en, this message translates to:
  /// **'No children registered yet.'**
  String get entityTreeNoChildren;

  /// No description provided for @entityTreeRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get entityTreeRefresh;

  /// No description provided for @entityTreeRoot.
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get entityTreeRoot;

  /// No description provided for @entityTreeLevel.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String entityTreeLevel(String level);

  /// No description provided for @entityTreeEntityCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entity} other{{count} entities}}'**
  String entityTreeEntityCount(int count);

  /// No description provided for @entityTreeChildrenCount.
  ///
  /// In en, this message translates to:
  /// **'{count} children'**
  String entityTreeChildrenCount(int count);

  /// No description provided for @entityTreeProductsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products'**
  String entityTreeProductsCount(int count);

  /// No description provided for @entityTreeActions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get entityTreeActions;

  /// No description provided for @entityTreeEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get entityTreeEdit;

  /// No description provided for @entityTreeManageUsers.
  ///
  /// In en, this message translates to:
  /// **'Manage Users'**
  String get entityTreeManageUsers;

  /// No description provided for @entityTreeAddChild.
  ///
  /// In en, this message translates to:
  /// **'Add Child'**
  String get entityTreeAddChild;

  /// No description provided for @entityTreeDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get entityTreeDelete;

  /// No description provided for @entityTreeIdent.
  ///
  /// In en, this message translates to:
  /// **'IDENT'**
  String get entityTreeIdent;

  /// No description provided for @entityTreeParentLabel.
  ///
  /// In en, this message translates to:
  /// **'PARENT'**
  String get entityTreeParentLabel;

  /// No description provided for @entityTreeAmendTitle.
  ///
  /// In en, this message translates to:
  /// **'Amend {typeName}'**
  String entityTreeAmendTitle(String typeName);

  /// No description provided for @entityTreeAddChildTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {typeName}'**
  String entityTreeAddChildTitle(String typeName);

  /// No description provided for @entityTreeDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete entity'**
  String get entityTreeDeleteTitle;

  /// No description provided for @entityTreeDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String entityTreeDeleteConfirm(String name);

  /// No description provided for @entityTreeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get entityTreeCancel;

  /// No description provided for @entityTreeDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Delete failed. Please try again.'**
  String get entityTreeDeleteFailed;

  /// No description provided for @entityTreeSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Hierarchy edit'**
  String get entityTreeSectionLabel;

  /// No description provided for @entityTreeFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get entityTreeFieldName;

  /// No description provided for @entityTreeFieldSlogan.
  ///
  /// In en, this message translates to:
  /// **'Slogan'**
  String get entityTreeFieldSlogan;

  /// No description provided for @entityTreeFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get entityTreeFieldDescription;

  /// No description provided for @entityTreeSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get entityTreeSave;

  /// No description provided for @entityTreeErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while saving.'**
  String get entityTreeErrorSaving;

  /// No description provided for @entityTreeColEntity.
  ///
  /// In en, this message translates to:
  /// **'ENTITY'**
  String get entityTreeColEntity;

  /// No description provided for @entityTreeColChildren.
  ///
  /// In en, this message translates to:
  /// **'CHILDREN'**
  String get entityTreeColChildren;

  /// No description provided for @entityTreeColVouchers.
  ///
  /// In en, this message translates to:
  /// **'VOUCHERS'**
  String get entityTreeColVouchers;

  /// No description provided for @entityFieldLogoUrl.
  ///
  /// In en, this message translates to:
  /// **'Logo URL'**
  String get entityFieldLogoUrl;

  /// No description provided for @entityFieldPrimaryColor.
  ///
  /// In en, this message translates to:
  /// **'Primary colour (hex)'**
  String get entityFieldPrimaryColor;

  /// No description provided for @entityFieldSecondaryColor.
  ///
  /// In en, this message translates to:
  /// **'Accent colour (hex)'**
  String get entityFieldSecondaryColor;

  /// No description provided for @entityFieldLowStockThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert level'**
  String get entityFieldLowStockThreshold;

  /// No description provided for @entityFieldLowStockThresholdHelp.
  ///
  /// In en, this message translates to:
  /// **'Flag a SKU as low when its available units fall below this. Leave empty for the default.'**
  String get entityFieldLowStockThresholdHelp;

  /// No description provided for @manageUsersSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'User register'**
  String get manageUsersSectionLabel;

  /// No description provided for @manageUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage users'**
  String get manageUsersTitle;

  /// No description provided for @manageUsersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No users on file. Register one below.'**
  String get manageUsersEmpty;

  /// No description provided for @manageUsersNewUser.
  ///
  /// In en, this message translates to:
  /// **'NEW USER'**
  String get manageUsersNewUser;

  /// No description provided for @manageUsersPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone *'**
  String get manageUsersPhone;

  /// No description provided for @manageUsersPassword.
  ///
  /// In en, this message translates to:
  /// **'Password *'**
  String get manageUsersPassword;

  /// No description provided for @manageUsersRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get manageUsersRole;

  /// No description provided for @manageUsersRegisterButton.
  ///
  /// In en, this message translates to:
  /// **'Register user'**
  String get manageUsersRegisterButton;

  /// No description provided for @manageUsersSave.
  ///
  /// In en, this message translates to:
  /// **'Save register'**
  String get manageUsersSave;

  /// No description provided for @manageUsersPhoneRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone is required'**
  String get manageUsersPhoneRequired;

  /// No description provided for @manageUsersPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get manageUsersPasswordRequired;

  /// No description provided for @manageUsersPhoneDuplicate.
  ///
  /// In en, this message translates to:
  /// **'A user with this phone already exists'**
  String get manageUsersPhoneDuplicate;

  /// No description provided for @manageUsersAtLeastOne.
  ///
  /// In en, this message translates to:
  /// **'At least one user is required'**
  String get manageUsersAtLeastOne;

  /// No description provided for @manageUsersErrorSaving.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while saving.'**
  String get manageUsersErrorSaving;

  /// No description provided for @batchAddEyebrow.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get batchAddEyebrow;

  /// No description provided for @batchAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add vouchers'**
  String get batchAddTitle;

  /// No description provided for @batchAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a single voucher by hand, or import a batch from an XLSX manifest.'**
  String get batchAddSubtitle;

  /// No description provided for @batchAddTabSingle.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get batchAddTabSingle;

  /// No description provided for @batchAddTabCsvXlsx.
  ///
  /// In en, this message translates to:
  /// **'CSV / XLSX'**
  String get batchAddTabCsvXlsx;

  /// No description provided for @batchAddDenomination.
  ///
  /// In en, this message translates to:
  /// **'Denomination'**
  String get batchAddDenomination;

  /// No description provided for @batchAddProductDefinition.
  ///
  /// In en, this message translates to:
  /// **'Product definition'**
  String get batchAddProductDefinition;

  /// No description provided for @batchAddImportedProducts.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} products!'**
  String batchAddImportedProducts(int count);

  /// No description provided for @batchAddCsvFormat.
  ///
  /// In en, this message translates to:
  /// **'Manifest format'**
  String get batchAddCsvFormat;

  /// No description provided for @batchAddRequiredColumns.
  ///
  /// In en, this message translates to:
  /// **'Required columns'**
  String get batchAddRequiredColumns;

  /// No description provided for @batchAddDownloadTemplate.
  ///
  /// In en, this message translates to:
  /// **'Download XLSX template'**
  String get batchAddDownloadTemplate;

  /// No description provided for @batchAddTemplateSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved.'**
  String get batchAddTemplateSaved;

  /// No description provided for @batchAddPickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick CSV / XLSX file'**
  String get batchAddPickFile;

  /// No description provided for @batchAddErrorReadBytes.
  ///
  /// In en, this message translates to:
  /// **'Could not read file bytes.'**
  String get batchAddErrorReadBytes;

  /// No description provided for @batchAddXlsxBadHeader.
  ///
  /// In en, this message translates to:
  /// **'XLSX must have \'serialNumber\' and \'pin\' header columns.'**
  String get batchAddXlsxBadHeader;

  /// No description provided for @batchAddDuplicateRow.
  ///
  /// In en, this message translates to:
  /// **'Row {index}: serial \'{serial}\' already exists in this entity\'s inventory.'**
  String batchAddDuplicateRow(int index, String serial);

  /// No description provided for @batchAddPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get batchAddPreview;

  /// No description provided for @batchAddRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String batchAddRowCount(int count);

  /// No description provided for @batchAddColSerial.
  ///
  /// In en, this message translates to:
  /// **'SERIAL'**
  String get batchAddColSerial;

  /// No description provided for @batchAddColPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get batchAddColPin;

  /// No description provided for @batchAddMoreRows.
  ///
  /// In en, this message translates to:
  /// **'+ {count} more rows'**
  String batchAddMoreRows(int count);

  /// No description provided for @batchAddProgressImported.
  ///
  /// In en, this message translates to:
  /// **'{done} / {total} imported'**
  String batchAddProgressImported(int done, int total);

  /// No description provided for @batchAddImportRows.
  ///
  /// In en, this message translates to:
  /// **'Import {count} rows'**
  String batchAddImportRows(int count);

  /// No description provided for @batchAddFailedAtRow.
  ///
  /// In en, this message translates to:
  /// **'Failed at row {index}: {error}'**
  String batchAddFailedAtRow(int index, String error);

  /// No description provided for @batchAddPrinting.
  ///
  /// In en, this message translates to:
  /// **'PRINTING'**
  String get batchAddPrinting;

  /// No description provided for @addVoucherDenomination.
  ///
  /// In en, this message translates to:
  /// **'Denomination'**
  String get addVoucherDenomination;

  /// No description provided for @addVoucherSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial number'**
  String get addVoucherSerial;

  /// No description provided for @addVoucherPin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get addVoucherPin;

  /// No description provided for @addVoucherSave.
  ///
  /// In en, this message translates to:
  /// **'Save voucher'**
  String get addVoucherSave;

  /// No description provided for @addVoucherSerialRequired.
  ///
  /// In en, this message translates to:
  /// **'Serial number is required'**
  String get addVoucherSerialRequired;

  /// No description provided for @addVoucherPinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required'**
  String get addVoucherPinRequired;

  /// No description provided for @addVoucherDuplicateSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial \'{serial}\' already exists in this entity\'s inventory.'**
  String addVoucherDuplicateSerial(String serial);

  /// No description provided for @addVoucherSaved.
  ///
  /// In en, this message translates to:
  /// **'Voucher saved.'**
  String get addVoucherSaved;

  /// No description provided for @defsFormTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New Definition'**
  String get defsFormTitleNew;

  /// No description provided for @defsFormTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Definition'**
  String get defsFormTitleEdit;

  /// No description provided for @defsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete definition'**
  String get defsDeleteTitle;

  /// No description provided for @defsDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This may break existing products.'**
  String defsDeleteConfirm(String name);

  /// No description provided for @defsCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get defsCancel;

  /// No description provided for @defsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get defsDelete;

  /// No description provided for @defsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Master record of voucher denominations issued by Inteshar Store.'**
  String get defsSubtitle;

  /// No description provided for @defsTitlesLabel.
  ///
  /// In en, this message translates to:
  /// **'titles'**
  String get defsTitlesLabel;

  /// No description provided for @defsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, SKU, or description…'**
  String get defsSearchHint;

  /// No description provided for @defsEmptyFirst.
  ///
  /// In en, this message translates to:
  /// **'No product definitions yet. Mint the first denomination.'**
  String get defsEmptyFirst;

  /// No description provided for @defsEmptySearch.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\".'**
  String defsEmptySearch(String query);

  /// No description provided for @defsAddFirst.
  ///
  /// In en, this message translates to:
  /// **'Add first'**
  String get defsAddFirst;

  /// No description provided for @defsNewDenomination.
  ///
  /// In en, this message translates to:
  /// **'New denomination'**
  String get defsNewDenomination;

  /// No description provided for @defsPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get defsPrice;

  /// No description provided for @defsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get defsEdit;

  /// No description provided for @defsMintLabel.
  ///
  /// In en, this message translates to:
  /// **'Mint a denomination'**
  String get defsMintLabel;

  /// No description provided for @defsAmendLabel.
  ///
  /// In en, this message translates to:
  /// **'Amend a denomination'**
  String get defsAmendLabel;

  /// No description provided for @defsFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get defsFieldName;

  /// No description provided for @defsFieldSku.
  ///
  /// In en, this message translates to:
  /// **'SKU * (e.g. AC5)'**
  String get defsFieldSku;

  /// No description provided for @defsFieldPrice.
  ///
  /// In en, this message translates to:
  /// **'Default Price (IQD) *'**
  String get defsFieldPrice;

  /// No description provided for @defsFieldDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get defsFieldDescription;

  /// No description provided for @defsFieldId.
  ///
  /// In en, this message translates to:
  /// **'ID (auto-generated)'**
  String get defsFieldId;

  /// No description provided for @defsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get defsSave;

  /// No description provided for @inventoryEyebrow.
  ///
  /// In en, this message translates to:
  /// **'The Counter'**
  String get inventoryEyebrow;

  /// No description provided for @inventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vouchers currently owned by this entity — search by name, SKU, or serial.'**
  String get inventorySubtitle;

  /// No description provided for @inventoryStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get inventoryStatusAvailable;

  /// No description provided for @inventoryStatusPrinted.
  ///
  /// In en, this message translates to:
  /// **'Printed'**
  String get inventoryStatusPrinted;

  /// No description provided for @inventoryStatusDamaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get inventoryStatusDamaged;

  /// No description provided for @inventoryStatusSentForPrinting.
  ///
  /// In en, this message translates to:
  /// **'Sent for printing'**
  String get inventoryStatusSentForPrinting;

  /// No description provided for @inventoryStatusFailedPrinting.
  ///
  /// In en, this message translates to:
  /// **'Print failed'**
  String get inventoryStatusFailedPrinting;

  /// No description provided for @inventorySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, SKU, or serial…'**
  String get inventorySearchHint;

  /// No description provided for @inventoryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get inventoryFilterAll;

  /// No description provided for @inventoryEmptyFirst.
  ///
  /// In en, this message translates to:
  /// **'No products held by this entity yet.'**
  String get inventoryEmptyFirst;

  /// No description provided for @inventoryEmptyFiltered.
  ///
  /// In en, this message translates to:
  /// **'No products match the current filters.'**
  String get inventoryEmptyFiltered;

  /// No description provided for @inventoryRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get inventoryRefresh;

  /// No description provided for @inventoryUnitCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unit} other{{count} units}}'**
  String inventoryUnitCount(int count);

  /// No description provided for @inventoryAvailableCount.
  ///
  /// In en, this message translates to:
  /// **'{count} available'**
  String inventoryAvailableCount(int count);

  /// No description provided for @inventoryPrintedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} printed'**
  String inventoryPrintedCount(int count);

  /// No description provided for @inventoryDamagedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} damaged'**
  String inventoryDamagedCount(int count);

  /// No description provided for @inventorySnLabel.
  ///
  /// In en, this message translates to:
  /// **'SN'**
  String get inventorySnLabel;

  /// No description provided for @inventoryChangeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get inventoryChangeStatus;

  /// No description provided for @inventoryMarkStatus.
  ///
  /// In en, this message translates to:
  /// **'Mark {status}'**
  String inventoryMarkStatus(String status);

  /// No description provided for @inventoryValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Inventory value'**
  String get inventoryValueLabel;

  /// No description provided for @inventoryValueUnits.
  ///
  /// In en, this message translates to:
  /// **'available units'**
  String get inventoryValueUnits;

  /// No description provided for @inventoryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get inventoryLoadMore;

  /// No description provided for @inventoryShowingCount.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total}'**
  String inventoryShowingCount(int shown, int total);

  /// No description provided for @inventoryNoCodes.
  ///
  /// In en, this message translates to:
  /// **'No codes to show.'**
  String get inventoryNoCodes;

  /// No description provided for @inventoryLoadCodesFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load codes.'**
  String get inventoryLoadCodesFailed;

  /// No description provided for @posHomeLiveCounter.
  ///
  /// In en, this message translates to:
  /// **'Live counter'**
  String get posHomeLiveCounter;

  /// No description provided for @posHomeSetupPrinter.
  ///
  /// In en, this message translates to:
  /// **'Setup printer'**
  String get posHomeSetupPrinter;

  /// No description provided for @posHomePickDenomination.
  ///
  /// In en, this message translates to:
  /// **'Pick a denomination'**
  String get posHomePickDenomination;

  /// No description provided for @posHomeCounterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Print at the counter from available stock.'**
  String get posHomeCounterSubtitle;

  /// No description provided for @posHomeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or SKU…'**
  String get posHomeSearchHint;

  /// No description provided for @posHomeInStock.
  ///
  /// In en, this message translates to:
  /// **'IN STOCK'**
  String get posHomeInStock;

  /// No description provided for @posHomeNoVouchers.
  ///
  /// In en, this message translates to:
  /// **'No available vouchers on the counter.'**
  String get posHomeNoVouchers;

  /// No description provided for @posHomeNoMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches \"{query}\".'**
  String posHomeNoMatches(String query);

  /// No description provided for @posHomePrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get posHomePrint;

  /// No description provided for @posHomeScratchNote.
  ///
  /// In en, this message translates to:
  /// **'Scratch only at point of redemption.'**
  String get posHomeScratchNote;

  /// No description provided for @posHomePrinterNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Printer not connected'**
  String get posHomePrinterNotConnected;

  /// No description provided for @posHomeCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get posHomeCancel;

  /// No description provided for @posHomePrinting.
  ///
  /// In en, this message translates to:
  /// **'Printing…'**
  String get posHomePrinting;

  /// No description provided for @posHomeUpdateError.
  ///
  /// In en, this message translates to:
  /// **'Could not update status: {error}'**
  String posHomeUpdateError(String error);

  /// No description provided for @posHomePrintFailed.
  ///
  /// In en, this message translates to:
  /// **'Print failed: {error}'**
  String posHomePrintFailed(String error);

  /// No description provided for @printerPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer setup'**
  String get printerPickerTitle;

  /// No description provided for @printerPickerConnectedManual.
  ///
  /// In en, this message translates to:
  /// **'Connected via manual address'**
  String get printerPickerConnectedManual;

  /// No description provided for @printerPickerConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String printerPickerConnectionFailed(String error);

  /// No description provided for @printerPickerConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String printerPickerConnectedTo(String name);

  /// No description provided for @printerPickerTestPrintSent.
  ///
  /// In en, this message translates to:
  /// **'Test print sent!'**
  String get printerPickerTestPrintSent;

  /// No description provided for @printerPickerPrintError.
  ///
  /// In en, this message translates to:
  /// **'Print error: {error}'**
  String printerPickerPrintError(String error);

  /// No description provided for @printerPickerConnected.
  ///
  /// In en, this message translates to:
  /// **'CONNECTED'**
  String get printerPickerConnected;

  /// No description provided for @printerPickerTestPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get printerPickerTestPrint;

  /// No description provided for @printerPickerDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get printerPickerDisconnect;

  /// No description provided for @printerPickerManualAddress.
  ///
  /// In en, this message translates to:
  /// **'Manual address'**
  String get printerPickerManualAddress;

  /// No description provided for @printerPickerManualHint.
  ///
  /// In en, this message translates to:
  /// **'Use this when the device is not visible in the scan list.'**
  String get printerPickerManualHint;

  /// No description provided for @printerPickerEnterMac.
  ///
  /// In en, this message translates to:
  /// **'Enter a MAC address'**
  String get printerPickerEnterMac;

  /// No description provided for @printerPickerMacFormat.
  ///
  /// In en, this message translates to:
  /// **'Format: XX:XX:XX:XX:XX:XX'**
  String get printerPickerMacFormat;

  /// No description provided for @printerPickerMacLabel.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth MAC address'**
  String get printerPickerMacLabel;

  /// No description provided for @printerPickerPair.
  ///
  /// In en, this message translates to:
  /// **'Pair'**
  String get printerPickerPair;

  /// No description provided for @printerPickerNearbyDevices.
  ///
  /// In en, this message translates to:
  /// **'Nearby devices'**
  String get printerPickerNearbyDevices;

  /// No description provided for @printerPickerRescan.
  ///
  /// In en, this message translates to:
  /// **'Re-scan'**
  String get printerPickerRescan;

  /// No description provided for @printerPickerNoDevices.
  ///
  /// In en, this message translates to:
  /// **'No devices found. Make sure Bluetooth is on and the printer is powered.'**
  String get printerPickerNoDevices;

  /// No description provided for @printerPickerUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get printerPickerUnknown;

  /// No description provided for @newTxnTitle.
  ///
  /// In en, this message translates to:
  /// **'New transaction'**
  String get newTxnTitle;

  /// No description provided for @newTxnIssueStock.
  ///
  /// In en, this message translates to:
  /// **'Issue stock'**
  String get newTxnIssueStock;

  /// No description provided for @newTxnIssueStockHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a destination, list the denominations, and submit. The server polls every second; allow up to 30 seconds for the ledger to settle.'**
  String get newTxnIssueStockHint;

  /// No description provided for @newTxnManifestLines.
  ///
  /// In en, this message translates to:
  /// **'Manifest lines'**
  String get newTxnManifestLines;

  /// No description provided for @newTxnAddLine.
  ///
  /// In en, this message translates to:
  /// **'Add line'**
  String get newTxnAddLine;

  /// No description provided for @newTxnGrandTotal.
  ///
  /// In en, this message translates to:
  /// **'Grand total'**
  String get newTxnGrandTotal;

  /// No description provided for @newTxnUnitsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} units'**
  String newTxnUnitsCount(int count);

  /// No description provided for @newTxnSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get newTxnSource;

  /// No description provided for @newTxnDestination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get newTxnDestination;

  /// No description provided for @newTxnNoChildren.
  ///
  /// In en, this message translates to:
  /// **'No downstream children'**
  String get newTxnNoChildren;

  /// No description provided for @newTxnNoChildrenHint.
  ///
  /// In en, this message translates to:
  /// **'Add a child via the hierarchy first'**
  String get newTxnNoChildrenHint;

  /// No description provided for @newTxnChooseEntity.
  ///
  /// In en, this message translates to:
  /// **'Choose entity'**
  String get newTxnChooseEntity;

  /// No description provided for @newTxnProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get newTxnProduct;

  /// No description provided for @newTxnQty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get newTxnQty;

  /// No description provided for @newTxnUnitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price (IQD)'**
  String get newTxnUnitPrice;

  /// No description provided for @newTxnLineTotal.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get newTxnLineTotal;

  /// No description provided for @newTxnPosting.
  ///
  /// In en, this message translates to:
  /// **'Posting…'**
  String get newTxnPosting;

  /// No description provided for @newTxnSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit transaction'**
  String get newTxnSubmit;

  /// No description provided for @newTxnPostedToLedger.
  ///
  /// In en, this message translates to:
  /// **'Posted to ledger'**
  String get newTxnPostedToLedger;

  /// No description provided for @newTxnDeclined.
  ///
  /// In en, this message translates to:
  /// **'Transaction declined'**
  String get newTxnDeclined;

  /// No description provided for @newTxnResultPosted.
  ///
  /// In en, this message translates to:
  /// **'posted'**
  String get newTxnResultPosted;

  /// No description provided for @newTxnResultDeclined.
  ///
  /// In en, this message translates to:
  /// **'declined'**
  String get newTxnResultDeclined;

  /// No description provided for @newTxnRef.
  ///
  /// In en, this message translates to:
  /// **'Ref · {id}'**
  String newTxnRef(String id);

  /// No description provided for @newTxnReturnToTransactions.
  ///
  /// In en, this message translates to:
  /// **'Return to transactions'**
  String get newTxnReturnToTransactions;

  /// No description provided for @txnsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Movements of stock to and from this entity, latest first.'**
  String get txnsSubtitle;

  /// No description provided for @txnsTallyOut.
  ///
  /// In en, this message translates to:
  /// **'out'**
  String get txnsTallyOut;

  /// No description provided for @txnsTallyIn.
  ///
  /// In en, this message translates to:
  /// **'in'**
  String get txnsTallyIn;

  /// No description provided for @txnsTallyDone.
  ///
  /// In en, this message translates to:
  /// **'done'**
  String get txnsTallyDone;

  /// No description provided for @txnsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No transactions on the ledger yet for this entity.'**
  String get txnsEmpty;

  /// No description provided for @txnsCreateAction.
  ///
  /// In en, this message translates to:
  /// **'Create transaction'**
  String get txnsCreateAction;

  /// No description provided for @txnsDirectionTo.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get txnsDirectionTo;

  /// No description provided for @txnsDirectionFrom.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get txnsDirectionFrom;

  /// No description provided for @txnsUnitLineSummary.
  ///
  /// In en, this message translates to:
  /// **'{units} {units, plural, =1{unit} other{units}} · {lines} {lines, plural, =1{line} other{lines}}'**
  String txnsUnitLineSummary(int units, int lines);

  /// No description provided for @txnsViewDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get txnsViewDetails;

  /// No description provided for @txnsDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Transaction details'**
  String get txnsDetailTitle;

  /// No description provided for @txnsFrom.
  ///
  /// In en, this message translates to:
  /// **'FROM'**
  String get txnsFrom;

  /// No description provided for @txnsTo.
  ///
  /// In en, this message translates to:
  /// **'TO'**
  String get txnsTo;

  /// No description provided for @txnsMetaReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get txnsMetaReference;

  /// No description provided for @txnsMetaIssued.
  ///
  /// In en, this message translates to:
  /// **'Issued'**
  String get txnsMetaIssued;

  /// No description provided for @txnsMetaNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get txnsMetaNote;

  /// No description provided for @txnsLineItems.
  ///
  /// In en, this message translates to:
  /// **'Line items'**
  String get txnsLineItems;

  /// No description provided for @txnsColSku.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get txnsColSku;

  /// No description provided for @txnsColQty.
  ///
  /// In en, this message translates to:
  /// **'QTY'**
  String get txnsColQty;

  /// No description provided for @txnsColUnit.
  ///
  /// In en, this message translates to:
  /// **'UNIT'**
  String get txnsColUnit;

  /// No description provided for @txnsColTotal.
  ///
  /// In en, this message translates to:
  /// **'TOTAL'**
  String get txnsColTotal;

  /// No description provided for @txnStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get txnStatusPending;

  /// No description provided for @txnStatusProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get txnStatusProcessing;

  /// No description provided for @txnStatusComplete.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get txnStatusComplete;

  /// No description provided for @txnStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get txnStatusFailed;

  /// No description provided for @appShellActiveEntity.
  ///
  /// In en, this message translates to:
  /// **'Active entity'**
  String get appShellActiveEntity;

  /// No description provided for @emptyStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get emptyStateTitle;

  /// No description provided for @errorStateErrorLabel.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorStateErrorLabel;

  /// No description provided for @errorStateTitle.
  ///
  /// In en, this message translates to:
  /// **'Something interrupted this request.'**
  String get errorStateTitle;

  /// No description provided for @vtTitle.
  ///
  /// In en, this message translates to:
  /// **'Voucher Templates'**
  String get vtTitle;

  /// No description provided for @vtSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Design the printed voucher for each product — header, fields, and a scannable QR.'**
  String get vtSubtitle;

  /// No description provided for @vtSelectPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a product to edit its template'**
  String get vtSelectPrompt;

  /// No description provided for @vtHeaderText.
  ///
  /// In en, this message translates to:
  /// **'Header text'**
  String get vtHeaderText;

  /// No description provided for @vtFields.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get vtFields;

  /// No description provided for @vtShowProductName.
  ///
  /// In en, this message translates to:
  /// **'Show product name'**
  String get vtShowProductName;

  /// No description provided for @vtShowSerial.
  ///
  /// In en, this message translates to:
  /// **'Show serial number'**
  String get vtShowSerial;

  /// No description provided for @vtShowPin.
  ///
  /// In en, this message translates to:
  /// **'Show PIN'**
  String get vtShowPin;

  /// No description provided for @vtShowPrice.
  ///
  /// In en, this message translates to:
  /// **'Show price'**
  String get vtShowPrice;

  /// No description provided for @vtQrSection.
  ///
  /// In en, this message translates to:
  /// **'QR code'**
  String get vtQrSection;

  /// No description provided for @vtQrEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enable QR'**
  String get vtQrEnabled;

  /// No description provided for @vtQrSource.
  ///
  /// In en, this message translates to:
  /// **'QR encodes'**
  String get vtQrSource;

  /// No description provided for @vtQrSourcePin.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get vtQrSourcePin;

  /// No description provided for @vtQrSourceSerial.
  ///
  /// In en, this message translates to:
  /// **'Serial'**
  String get vtQrSourceSerial;

  /// No description provided for @vtQrPrefix.
  ///
  /// In en, this message translates to:
  /// **'QR prefix'**
  String get vtQrPrefix;

  /// No description provided for @vtQrSuffix.
  ///
  /// In en, this message translates to:
  /// **'QR suffix'**
  String get vtQrSuffix;

  /// No description provided for @vtQrExample.
  ///
  /// In en, this message translates to:
  /// **'Scans as'**
  String get vtQrExample;

  /// No description provided for @vtRedeemInstructions.
  ///
  /// In en, this message translates to:
  /// **'Redeem instructions'**
  String get vtRedeemInstructions;

  /// No description provided for @vtFooterText.
  ///
  /// In en, this message translates to:
  /// **'Footer text'**
  String get vtFooterText;

  /// No description provided for @vtPreview.
  ///
  /// In en, this message translates to:
  /// **'Live preview'**
  String get vtPreview;

  /// No description provided for @vtSave.
  ///
  /// In en, this message translates to:
  /// **'Save template'**
  String get vtSave;

  /// No description provided for @vtSaved.
  ///
  /// In en, this message translates to:
  /// **'Template saved'**
  String get vtSaved;

  /// No description provided for @vtSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save template'**
  String get vtSaveFailed;

  /// No description provided for @vtEmpty.
  ///
  /// In en, this message translates to:
  /// **'No products yet — create one in the Catalog first.'**
  String get vtEmpty;

  /// No description provided for @dashKpiStock.
  ///
  /// In en, this message translates to:
  /// **'Vouchers in stock'**
  String get dashKpiStock;

  /// No description provided for @dashKpiTransactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get dashKpiTransactions;

  /// No description provided for @dashKpiLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low-stock SKUs'**
  String get dashKpiLowStock;

  /// No description provided for @dashPlatformOverview.
  ///
  /// In en, this message translates to:
  /// **'Platform overview'**
  String get dashPlatformOverview;

  /// No description provided for @dashKpiDirectChildren.
  ///
  /// In en, this message translates to:
  /// **'direct children'**
  String get dashKpiDirectChildren;

  /// No description provided for @dashKpiSkusCount.
  ///
  /// In en, this message translates to:
  /// **'{count} SKUs'**
  String dashKpiSkusCount(int count);

  /// No description provided for @dashKpiThisAccount.
  ///
  /// In en, this message translates to:
  /// **'this account'**
  String get dashKpiThisAccount;

  /// No description provided for @dashKpiAllHealthy.
  ///
  /// In en, this message translates to:
  /// **'all healthy'**
  String get dashKpiAllHealthy;

  /// No description provided for @dashKpiNeedsAttention.
  ///
  /// In en, this message translates to:
  /// **'needs attention'**
  String get dashKpiNeedsAttention;

  /// No description provided for @dashRecentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get dashRecentTransactions;

  /// No description provided for @dashLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get dashLowStock;

  /// No description provided for @dashViewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get dashViewAll;

  /// No description provided for @dashColRoute.
  ///
  /// In en, this message translates to:
  /// **'Route'**
  String get dashColRoute;

  /// No description provided for @dashColSku.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get dashColSku;

  /// No description provided for @dashColQty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get dashColQty;

  /// No description provided for @dashColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get dashColStatus;

  /// No description provided for @dashColAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get dashColAmount;

  /// No description provided for @dashUnitsLeft.
  ///
  /// In en, this message translates to:
  /// **'left'**
  String get dashUnitsLeft;

  /// No description provided for @dashAllHealthy.
  ///
  /// In en, this message translates to:
  /// **'All stock levels healthy'**
  String get dashAllHealthy;

  /// No description provided for @dashNoTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get dashNoTransactions;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
