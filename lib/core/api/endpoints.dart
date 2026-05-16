class Endpoints {
  static const login = '/api/auth/login';

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

  static const definitionCreate = '/api/inventory/definition/create';
  static const definitionRead = '/api/inventory/definition/read';
  static const definitionReadAll = '/api/inventory/definition/readall';
  static const definitionUpdate = '/api/inventory/definition/update';
  static const definitionDelete = '/api/inventory/definition/delete';

  static const productCreate = '/api/inventory/product/create';
  static const productRead = '/api/inventory/product/read';
  static const productReadAll = '/api/inventory/product/readall';
  static const productReadByEntity = '/api/inventory/product/readByEntity';
  static const productUpdate = '/api/inventory/product/update';
  static const productDelete = '/api/inventory/product/delete';

  static const transactionCreate = '/api/transactions/create';
  static const transactionRead = '/api/transactions/read';
  static const transactionReadAll = '/api/transactions/readall';
  static const transactionUpdate = '/api/transactions/update';
  static const transactionDelete = '/api/transactions/delete';
}
