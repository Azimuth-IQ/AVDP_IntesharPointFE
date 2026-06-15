// Sunmi InnerPrinter (P/V series). Binder transaction codes are positional, so
// the declared order and count up to sendRAWData MUST match Sunmi's canonical
// interface. We only call printerInit (#4), lineWrap (#10) and sendRAWData (#11);
// the earlier methods are kept as correctly-ordered placeholders. Methods beyond
// #11 (which pull in TransBean/ITax/Bitmap) are intentionally omitted — dropping
// trailing methods does not shift the codes of the ones above.
package woyou.aidlservice.jiuiv5;

import woyou.aidlservice.jiuiv5.ICallback;

interface IWoyouService {
    boolean postPrintData(String packageName, in byte[] data, int offset, int length);
    int getFirmwareStatus();
    String getServiceVersion();
    void printerInit(in ICallback callback);
    void printerSelfChecking(in ICallback callback);
    String getPrinterSerialNo();
    String getPrinterVersion();
    String getPrinterModal();
    void getPrintedLength(in ICallback callback);
    void lineWrap(int n, in ICallback callback);
    void sendRAWData(in byte[] data, in ICallback callback);
}
