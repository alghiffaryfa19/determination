package com.aurora.companion;

/** Trusted-app facade over the native Aurora control protocol. */
interface IAuroraControl {
    String getStatusJson();
    String getCapabilitiesJson();
    String getMetricsJson();
    int requestMode(String target);
}
