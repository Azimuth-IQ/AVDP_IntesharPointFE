class Endpoints {
  static const login = '/api/auth/login';
  static const logout = '/api/auth/logout';
  static const changePassword = '/api/auth/change-password';
  static const authSetPin = '/api/auth/set-pin';
  static const authVerifyPin = '/api/auth/verify-pin';
  // B-054 (A8): public, rate-limited; notifies the shop's parent agent.
  static const authForgotPassword = '/api/auth/forgot-password';

  static const healthGeneral = '/api/health/general';
  static const healthRam = '/api/health/ram';
  static const healthCpu = '/api/health/cpu';
  static const healthStorage = '/api/health/storage';

  static const entityCreate = '/api/entity/create';
  static const entityRead = '/api/entity/read';
  static const entityMe = '/api/entity/me'; // the caller's own entity (B-023)
  static const entityReadAll = '/api/entity/readall';
  // B-023 P1 paged reads: server-side picker search (HQ global, others own
  // subtree) and direct children for the load-on-expand hierarchy tree.
  static const entitySearch = '/api/entity/search';
  static const entityChildren = '/api/entity/children';
  static const entityReadWithChildren = '/api/entity/readwithchildren';
  /// The caller's own ancestor chain as display rows (id/name/type), nearest first.
  /// Replaces reading a parent's whole document just to print its name.
  static const entityChain = '/api/entity/chain';
  static const entityBranding = '/api/entity/branding';

  // POS slider management (HQ-only). The POS itself gets resolved sliders via
  // entityBranding at login — it never calls these.
  static const slider = '/api/slider';
  static const sliderReorder = '/api/slider/reorder';
  static const entityUpdate = '/api/entity/update';
  static const entityDelete = '/api/entity/delete';
  // Point (STORE/POS) management
  static const entitySetActive = '/api/entity/setActive';
  static const entityResetPassword = '/api/entity/resetPassword';
  // HQ users / supervisors management
  static const entityUsers = '/api/entity/users';
  static const entityUserAdd = '/api/entity/users/add';
  static const entityUserUpdate = '/api/entity/users/update';
  static const entityUserRemove = '/api/entity/users/remove';
  static const entityUserResetTotp = '/api/entity/users/resetTotp';
  static const entityPosStats = '/api/entity/posStats';

  static const definitionCreate = '/api/inventory/definition/create';
  static const definitionRead = '/api/inventory/definition/read';
  static const definitionReadAll = '/api/inventory/definition/readall';
  static const definitionUpdate = '/api/inventory/definition/update';
  static const definitionDelete = '/api/inventory/definition/delete';
  // B-081: per-agent voucher-definition visibility (HQ-only).
  static const definitionRestrict = '/api/inventory/definition/restrict';
  static const definitionRestrictions = '/api/inventory/definition/restrictions';

  static const productCreate = '/api/inventory/product/create';
  static const productBatch = '/api/inventory/product/batch';
  static const productRead = '/api/inventory/product/read';
  static const productReadByEntity = '/api/inventory/product/readByEntity';
  static const productSummaryByEntity = '/api/inventory/product/summaryByEntity';
  static const productReadByEntityAndSku = '/api/inventory/product/readByEntityAndSku';
  // Draw-on-print (pool model): a POS/sub-agent sells BY SKU, drawing one card from its
  // parent Main Agent's pool and debiting its withdrawal limit. Sellable = the SKUs it can
  // sell; draw = the atomic sale; draw/recover = lost-response idempotency re-fetch.
  static const productSellable = '/api/inventory/product/sellable';
  static const productDraw = '/api/inventory/product/draw';
  static const productDrawRecover = '/api/inventory/product/draw/recover';
  // B-086 bulk sale: pre-flight quote, the batched draw, and whole-batch recovery.
  static const productBulkQuote = '/api/inventory/product/bulk-quote';
  static const productDrawBulk = '/api/inventory/product/draw-bulk';
  static const productDrawRecoverBatch = '/api/inventory/product/draw/recover-batch';
  static const productPrintOperations = '/api/inventory/product/print-operations';
  static const productConfirmPrint = '/api/inventory/product/confirmPrint';
  // Correcting a single voucher. These replace the general product/update and
  // product/delete, which are disabled server-side — the row menu used to call
  // update and simply got a 403.
  static const productSetStatus = '/api/inventory/product/setStatus';
  static const productSetPin = '/api/inventory/product/setPin';

  static const transactionCreate = '/api/transactions/create';
  static const transactionRead = '/api/transactions/read';
  static const transactionReadAll = '/api/transactions/readall';
  // B-023 P1: paged list (same tenancy as readall) + dashboard recent-N.
  static const transactionPage = '/api/transactions/page';
  static const transactionRecent = '/api/transactions/recent';
  static const transactionFeed = '/api/transactions/feed';
  static const transactionUpdate = '/api/transactions/update';
  static const transactionDelete = '/api/transactions/delete';

  static const logClient = '/api/logs/client';
  static const logQuery = '/api/logs';
  static const logRead = '/api/logs/read';

  // System Activity (HQ BFF, admin-only)
  static const entitySummary = '/api/entity/summary';
  static const adminOverview = '/api/admin/overview';
  static const adminUsers = '/api/admin/users';

  // App self-update (public GETs)
  static const appLatest = '/api/app/latest';
  static const appCheck = '/api/app/check';
  static const appDownload = '/api/app/download'; // public 302 → latest APK

  // Pricing / virtual balance
  static const companyCreate = '/api/company/create';
  static const companyReadAll = '/api/company/readall';
  static const companyUpdate = '/api/company/update';
  static const companyDelete = '/api/company/delete';
  static const companyRestrict = '/api/company/restrict';      // B-058 per-agent restriction
  static const companyRestrictions = '/api/company/restrictions';
  static const pricingCatalog = '/api/pricing/catalog';
  static const pricingSet = '/api/pricing/set';
  static const pricingSetBulk = '/api/pricing/set-bulk';       // B-059 Excel bulk apply
  static const pricingUnpricedAgents = '/api/pricing/unpriced-agents'; // B-060 HQ oversight
  static const balance = '/api/balance';
  static const balanceGrant = '/api/balance/grant';
  static const balanceGrants = '/api/balance/grants';

  // POS-user quota + management
  static const posQuota = '/api/pos-quota';
  static const posQuotaGrant = '/api/pos-quota/grant';
  static const posQuotaGrants = '/api/pos-quota/grants';
  // HQ network oversight (B-029): all agents' POS-slot rollup
  static const posQuotaNetwork = '/api/pos-quota/network';
  static const posQuotaNetworkSummary = '/api/pos-quota/network/summary';
  static const posUsersList = '/api/pos-users/list'; // STORE children of a host agent (B-052)
  static const posUsersListPaged = '/api/pos-users/list/page'; // paged variant (B-023 P2)
  static const posUsersOnboard = '/api/pos-users/onboard';
  static const posUsersUpdate = '/api/pos-users/update';
  static const posUsersRevoke = '/api/pos-users/revoke';
  static const posUsersResetPin = '/api/pos-users/reset-pin';
  static const posUsersResetTotp = '/api/pos-users/reset-totp';
  static const posUsersResetPassword = '/api/pos-users/reset-password';
  // B-054 POS self endpoints (STORE-scoped server-side)
  static const posConfirmLocation = '/api/pos/confirm-location';
  static const posStatement = '/api/pos/statement';

  // Chat / التواصل (B-057) — pairing enforced server-side
  static const chatThreads = '/api/chat/threads';
  static const chatMessages = '/api/chat/messages';
  static const chatSend = '/api/chat/send';
  static const chatRead = '/api/chat/read';

  // Reports (التقارير)
  static const reportsBalances = '/api/reports/balances';
  static const reportsTransfers = '/api/reports/transfers';
  static const reportsSales = '/api/reports/sales';
  static const reportsUploads = '/api/reports/uploads';

  // Object storage
  static const storageUpload = '/api/storage/upload';

  // Voucher import batches (HQ-only). pause handles resume too via ?paused=.
  static const productBatches = '/api/inventory/batches';
  static const productBatchPause = '/api/inventory/batch/pause';
  static const productBatchDelete = '/api/inventory/batch';
  static const productBatchWithdraw = '/api/inventory/batch/withdraw';
  static const productBatchExport = '/api/inventory/batch/export';

  // Broadcast notifications. GET inbox + POST create share the base path;
  // mark-read is POST /api/notifications/{id}/read (built in the repository).
  static const notifications = '/api/notifications';
  static const notificationsSend = '/api/notifications';

  // Platform settings: the global working-hours toggle is a generic key/value
  // setting; the per-entity window is a targeted patch on the entity.
  static const settingsWorkingHours = '/api/settings/auth.workinghours.enabled';
  static const settingsWorkingHoursEntity = '/api/entity/workingHours';
  /// B-107: per-tier 2FA requirement. `<TIER>` is an EntityType name.
  static String settingsTotpRequired(String tier) =>
      '/api/settings/auth.totp.required.\$tier';
}
