package woyou.aidlservice.jiuiv5;

// Sunmi InnerPrinter result callback (verbatim from Sunmi's public AIDL).
interface ICallback {
    oneway void onRunResult(boolean isSuccess);
    oneway void onReturnString(String result);
    oneway void onRaiseException(int code, String msg);
    oneway void onPrintResult(int code, String msg);
}
