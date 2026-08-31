// Pulls listings out of a Facebook Marketplace search results page.
//
// Facebook's class names are obfuscated and change often, so this anchors on
// the things that are structural rather than cosmetic:
//
//   - every result links to /marketplace/item/<id>
//   - inside a card, the price is the first `span[dir="auto"]`, and the title
//     and location are the two `span[aria-hidden="true"]` rows, in that
//     order (the card's own aria-label repeats them: "<title>, <price>,
//     <location>, listing <id>"). A listing with no title has an empty first
//     row — it must not be given the location as a title.
//   - a search with too few matches is padded with unrelated listings under a
//     rendered "Results from outside your search" line; everything after
//     that line is not a result. A search with none at all says "No results
//     found for" above the padding.
//
// Cards that predate the aria-hidden rows fall back to reading the anchor's
// text in order: price first, then title, then location.
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

  function spanWithText(text) {
    var spans = document.querySelectorAll("span");
    for (var i = 0; i < spans.length; i++) {
      if (spans[i].textContent.trim() === text) return spans[i];
    }
    return null;
  }

  function isAfter(node, marker) {
    return (marker.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) !== 0;
  }

  function fromRows(anchor) {
    var rows = anchor.querySelectorAll('span[aria-hidden="true"]');
    if (rows.length < 2) return null;
    var price = "";
    var priceSpans = anchor.querySelectorAll('span[dir="auto"]');
    for (var i = 0; i < priceSpans.length; i++) {
      var value = priceSpans[i].textContent.trim();
      if (looksLikePrice(value)) {
        price = value;
        break;
      }
    }
    return {
      title: rows[0].textContent.trim(),
      price: price,
      location: rows[1].textContent.trim(),
    };
  }

  function fromText(anchor) {
    var pieces = textPieces(anchor);
    var price = "";
    var rest = [];
    for (var p = 0; p < pieces.length; p++) {
      if (!price && looksLikePrice(pieces[p])) price = pieces[p];
      else rest.push(pieces[p]);
    }
    return {
      title: rest.length > 0 ? rest[0] : "",
      price: price,
      location: rest.length > 1 ? rest[rest.length - 1] : "",
    };
  }

  var noResults = false;
  var spans = document.querySelectorAll("span");
  for (var s = 0; s < spans.length; s++) {
    if (/^No results found for\b/.test(spans[s].textContent.trim())) {
      noResults = true;
      break;
    }
  }
  if (noResults) return JSON.stringify([]);

  var outsideMarker = spanWithText("Results from outside your search");

  var seen = {};
  var results = [];
  var anchors = document.querySelectorAll('a[href*="/marketplace/item/"]');

  for (var i = 0; i < anchors.length; i++) {
    var anchor = anchors[i];
    var match = anchor.getAttribute("href").match(/\/marketplace\/item\/(\d+)/);
    if (!match) continue;
    if (outsideMarker && isAfter(anchor, outsideMarker)) continue;
    var id = match[1];
    if (seen[id]) continue;
    seen[id] = true;

    var fields = fromRows(anchor) || fromText(anchor);
    var image = anchor.querySelector("img");

    results.push({
      id: id,
      title: fields.title,
      price: fields.price,
      location: fields.location,
      url: "https://www.facebook.com/marketplace/item/" + id,
      imageURL: image ? image.getAttribute("src") : null,
    });
  }

  return JSON.stringify(results);
})();
