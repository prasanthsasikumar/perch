// Pulls listings out of a Facebook Marketplace search results page.
//
// Facebook's class names are obfuscated and change often, so this anchors on
// the one thing that is structural rather than cosmetic: every result links to
// /marketplace/item/<id>. Everything else is read from the anchor's own text,
// in the order Facebook renders it — price first, then title, then location.
//
// Returns a JSON string, because that is what evaluateJavaScript can hand back
// across the bridge without ceremony.
(function () {
  function textPieces(anchor) {
    // Visible, non-empty strings in document order, de-duplicated.
    var out = [];
    var walker = document.createTreeWalker(anchor, NodeFilter.SHOW_TEXT, null);
    var node;
    while ((node = walker.nextNode())) {
      var value = node.textContent.trim();
      if (value && out.indexOf(value) === -1) out.push(value);
    }
    return out;
  }

  function looksLikePrice(value) {
    return /^(free|\$|£|€|₹)/i.test(value) || /^[\d,]+(\.\d+)?$/.test(value);
  }

  var seen = {};
  var results = [];
  var anchors = document.querySelectorAll('a[href*="/marketplace/item/"]');

  for (var i = 0; i < anchors.length; i++) {
    var anchor = anchors[i];
    var match = anchor.getAttribute("href").match(/\/marketplace\/item\/(\d+)/);
    if (!match) continue;
    var id = match[1];
    if (seen[id]) continue;
    seen[id] = true;

    var pieces = textPieces(anchor);
    var price = "";
    var rest = [];
    for (var p = 0; p < pieces.length; p++) {
      if (!price && looksLikePrice(pieces[p])) price = pieces[p];
      else rest.push(pieces[p]);
    }

    var image = anchor.querySelector("img");

    results.push({
      id: id,
      title: rest.length > 0 ? rest[0] : "",
      price: price,
      location: rest.length > 1 ? rest[rest.length - 1] : "",
      url: "https://www.facebook.com/marketplace/item/" + id,
      imageURL: image ? image.getAttribute("src") : null,
    });
  }

  return JSON.stringify(results);
})();
