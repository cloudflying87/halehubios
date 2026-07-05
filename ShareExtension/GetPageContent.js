// Runs inside the live Safari tab when shared from Safari, so it captures the
// FULLY RENDERED DOM (after the site's JavaScript has run) — same as the old
// Shortcut's "Run JavaScript on Web Page" with document.documentElement.outerHTML.
// The returned dictionary arrives in the extension as the JS preprocessing result.
var GetPageContent = function () {};

GetPageContent.prototype = {
    run: function (args) {
        args.completionFunction({
            "html": document.documentElement.outerHTML,
            "url": document.URL,
            "title": document.title
        });
    },
    // Called after the extension finishes; nothing to clean up.
    finalize: function (args) {}
};

var ExtensionPreprocessingJS = new GetPageContent();
