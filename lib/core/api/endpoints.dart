class Endpoints {
  static const login = '/api/auth/login';
  static const logout = '/api/auth/logout';
  static const changePassword = '/api/auth/change-password';
  static const authSetPin = '/api/auth/set-pin';
  static const authVerifyPin = '/api/auth/verify-pin';

  static const healthGeneral = '/api/health/general';
  static const healthRam = '/api/health/ram';
  static const healthCpu = '/api/health/cpu';
  static const healthStorage = '/api/health/storage';

  static const entityCreate = '/api/entity/create';
  static const entityRead = '/api/entity/read';
  static const entityReadAll = '/api/entity/readall';
  static const entityReadWithChildren = '/api/entity/readwithchildren';
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

  static const productCreate = '/api/inventory/product/create';
  static const productBatch = '/api/inventory/product/batch';
  static const productRead = '/api/inventory/product/read';
  static const productReadAll = '/api/inventory/product/readall';
  static const productReadByEntity = '/api/inventory/product/readByEntity';
  static const productSummaryByEntity = '/api/inventory/product/summaryByEntity';
  static const productReadByEntityAndSku = '/api/inventory/product/readByEntityAndSku';
  static const productSendForPrinting = '/api/inventory/product/sendForPrinting';
  // Draw-on-print (pool model): a POS/sub-agent sells BY SKU, drawing one card from its
  // parent Main Agent's pool and debiting its withdrawal limit. Sellable = the SKUs it can
  // sell; draw = the atomic sale; draw/recover = lost-response idempotency re-fetch.
  static const productSellable = '/api/inventory/product/sellable';
  static const productDraw = '/api/inventory/product/draw';
  static const productDrawRecover = '/api/inventory/product/draw/recover';
  static const productPrintOperations = '/api/inventory/product/print-operations';
  static const productConfirmPrint = '/api/inventory/product/confirmPrint';
  static const productUpdate = '/api/inventory/product/update';
  static const productDelete = '/api/inventory/product/delete';

  static const transactionCreate = '/api/transactions/create';
  static const transactionRead = '/api/transactions/read';
  static const transactionReadAll = '/api/transactions/readall';
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

  // Pricing / virtual balance
  static const companyCreate = '/api/company/create';
  static const companyReadAll = '/api/company/readall';
  static const companyUpdate = '/api/company/update';
  static const companyDelete = '/api/company/delete';
  static const pricingCatalog = '/api/pricing/catalog';
  static const pricingSet = '/api/pricing/set';
  static const balance = '/api/balance';
  static const balanceGrant = '/api/balance/grant';
  static const balanceGrants = '/api/balance/grants';

  // Reports (التقارير)
  static const reportsBalances = '/api/reports/balances';
  static const reportsTransfers = '/api/reports/transfers';

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
}
