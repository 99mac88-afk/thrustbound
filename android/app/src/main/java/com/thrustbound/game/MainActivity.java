package com.thrustbound.game;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.view.WindowManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;

/**
 * Thrustbound for Android: the same game as the website, served from inside the APK
 * so it works offline. Files are served from a private https address so that
 * saved progress, JavaScript modules and the community server all work.
 */
public class MainActivity extends Activity {
    /** Reserved by Android for exactly this purpose: it can never be a real website. */
    private static final String HOST = "appassets.androidplatform.net";
    private static final String START = "https://" + HOST + "/index.html";
    private static final Map<String, String> TYPES = new HashMap<>();

    static {
        TYPES.put("html", "text/html");
        TYPES.put("js", "text/javascript");
        TYPES.put("css", "text/css");
        TYPES.put("json", "application/json");
        TYPES.put("webmanifest", "application/manifest+json");
        TYPES.put("png", "image/png");
        TYPES.put("wav", "audio/wav");
        TYPES.put("svg", "image/svg+xml");
    }

    private WebView web;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);

        web = new WebView(this);
        web.setBackgroundColor(0xFF040714);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setSupportZoom(false);
        s.setBuiltInZoomControls(false);
        s.setTextZoom(100);
        // Lets the page know it runs inside the app (it then hides "get the app").
        s.setUserAgentString(s.getUserAgentString() + " ThrustboundApp/" + BuildConfig.VERSION_NAME);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (!HOST.equals(uri.getHost())) {
                    return null; // the community server and anything else go to the network
                }
                return asset(uri.getPath());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                if (HOST.equals(uri.getHost())) {
                    return false;
                }
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, uri));
                } catch (ActivityNotFoundException ignored) {
                    // No browser installed: nothing to do.
                }
                return true;
            }
        });

        setContentView(web);
        if (savedInstanceState != null) {
            web.restoreState(savedInstanceState);
        } else {
            web.loadUrl(START);
        }
    }

    private WebResourceResponse asset(String path) {
        if (path == null || path.isEmpty() || path.equals("/")) {
            path = "/index.html";
        }
        if (path.contains("..")) {
            return notFound();
        }
        String ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
        String type = TYPES.containsKey(ext) ? TYPES.get(ext) : "application/octet-stream";
        try {
            InputStream in = getAssets().open("www" + path);
            WebResourceResponse response = new WebResourceResponse(type, type.startsWith("text/") || type.contains("json") ? "UTF-8" : null, in);
            Map<String, String> headers = new HashMap<>();
            headers.put("Cache-Control", "no-cache");
            headers.put("Access-Control-Allow-Origin", "*");
            response.setResponseHeaders(headers);
            return response;
        } catch (IOException e) {
            return notFound();
        }
    }

    private static WebResourceResponse notFound() {
        WebResourceResponse r = new WebResourceResponse("text/plain", "UTF-8", null);
        r.setStatusCodeAndReasonPhrase(404, "Not Found");
        return r;
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        // Let the game go back a screen (or pause); leave the app only from the main menu.
        web.evaluateJavascript("(window.__thrustboundBack ? window.__thrustboundBack() : false)", value -> {
            if (!"true".equals(value)) {
                finish();
            }
        });
    }

    @Override
    protected void onPause() {
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    protected void onDestroy() {
        web.destroy();
        super.onDestroy();
    }
}
