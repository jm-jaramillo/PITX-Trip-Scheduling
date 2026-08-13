// Client-side OCR for LTO OR/CR photos - no server, no API key, no per-scan
// cost. Trade-off: Tesseract.js does raw text recognition with no idea what
// a "plate number" is, so the guesses below are heuristics over messy OCR
// output, not a reliable parse. The UI always shows these as an editable,
// reviewable starting point - never auto-saved without the operator seeing
// them - and the raw text is shown too so a bad guess can be corrected by
// eye rather than by re-scanning.

import { createWorker } from "https://esm.sh/tesseract.js@5.1.1";

const COMMON_MAKES = [
  "TOYOTA", "MITSUBISHI", "ISUZU", "HYUNDAI", "NISSAN", "FUSO", "HINO",
  "YUTONG", "KIA", "FOTON", "SUZUKI", "FORD", "MAN", "DAEWOO", "HIGER",
  "GOLDEN DRAGON", "JAC", "KING LONG",
];

const BODY_TYPES = [
  "BUS", "MINIBUS", "COASTER", "VAN", "UV EXPRESS", "JEEPNEY", "SUV",
  "SEDAN", "TRUCK", "MPV", "AUV", "PICKUP",
];

/**
 * Runs OCR on an image file and returns both the raw text and best-effort
 * field guesses. `onProgress(text)` is called with short status updates
 * ("Loading…", "Recognizing text… 42%", etc.) if provided.
 */
export async function extractOrCr(file, onProgress) {
  const worker = await createWorker("eng", 1, {
    logger: (msg) => {
      if (!onProgress) return;
      if (msg.status === "recognizing text") {
        onProgress(`Reading document… ${Math.round((msg.progress ?? 0) * 100)}%`);
      } else if (msg.status) {
        onProgress(msg.status[0].toUpperCase() + msg.status.slice(1) + "…");
      }
    },
  });

  try {
    const {
      data: { text },
    } = await worker.recognize(file);
    return { rawText: text, guesses: parseOrCrText(text) };
  } finally {
    await worker.terminate();
  }
}

function parseOrCrText(rawText) {
  const text = rawText.replace(/\r/g, "");
  const upper = text.toUpperCase();
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);

  return {
    plate_no: guessPlate(upper),
    make_model: guessMakeModel(upper, lines),
    body_type: guessBodyType(upper),
    // Specific labels first (checked across every line before falling back
    // to a descriptive phrase); "0.R" / "0R" cover Tesseract commonly
    // misreading O as 0 in this position.
    or_number: guessLabeledNumber(
      lines,
      ["O.R. NO", "0.R. NO", "OR NO", "0R NO", "OR NUMBER", "OR#"],
      ["OFFICIAL RECEIPT"]
    ),
    cr_number: guessLabeledNumber(
      lines,
      ["C.R. NO", "CR NO", "CR NUMBER", "CR#"],
      ["CERTIFICATE OF REGISTRATION"]
    ),
    expiry: guessExpiry(upper),
  };
}

function guessPlate(upper) {
  // Philippine plates: 3 letters + 3-4 digits, with or without a separator
  // ("NGP 2481", "NGP2481", "NGP-2481"). Word boundaries avoid matching
  // mid-word fragments from noisy OCR text.
  const match = upper.match(/\b([A-Z]{2,3})[\s-]?(\d{3,4})\b/);
  if (!match) return null;
  return `${match[1]} ${match[2]}`;
}

function guessMakeModel(upper, lines) {
  const make = COMMON_MAKES.find((m) => upper.includes(m));
  if (!make) return null;

  // Often the model/series sits right after the make on the same OCR line.
  const line = lines.find((l) => l.toUpperCase().includes(make));
  if (line) {
    const idx = line.toUpperCase().indexOf(make);
    const rest = line.slice(idx + make.length).trim().replace(/^[:\-]\s*/, "");
    if (rest && rest.length < 30) return `${titleCase(make)} ${rest}`;
  }
  return titleCase(make);
}

function guessBodyType(upper) {
  const type = BODY_TYPES.find((t) => upper.includes(t));
  return type ? titleCase(type) : null;
}

/**
 * Finds a line mentioning one of `labels` (e.g. "OR NO") and pulls the
 * longest run of digits from that line or the next one - OCR frequently
 * splits a label and its value across lines.
 *
 * `primaryLabels` are specific abbreviations, checked against every line
 * first. `fallbackLabels` are full descriptive phrases (e.g. "CERTIFICATE
 * OF REGISTRATION") that only get tried if nothing else matched - on a
 * real document that phrase is usually the title, not adjacent to the
 * actual number, so it's a last resort rather than a first guess.
 */
function guessLabeledNumber(lines, primaryLabels, fallbackLabels = []) {
  for (const labels of [primaryLabels, fallbackLabels]) {
    for (let i = 0; i < lines.length; i++) {
      const lineUpper = lines[i].toUpperCase();
      if (!labels.some((l) => lineUpper.includes(l))) continue;

      const here = longestDigitRun(lines[i]);
      if (here) return here;
      const next = lines[i + 1] ? longestDigitRun(lines[i + 1]) : null;
      if (next) return next;
    }
  }
  return null;
}

function longestDigitRun(line) {
  // At least 5 digits: OR/CR numbers run longer than that in practice, and
  // this keeps a 3-4 digit plate fragment on the same or an adjacent line
  // from being mistaken for one.
  const runs = line.match(/\d{5,}/g);
  if (!runs) return null;
  return runs.reduce((a, b) => (b.length > a.length ? b : a));
}

function guessExpiry(upper) {
  const dates = [...upper.matchAll(/\b(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})\b/g)];
  if (dates.length === 0) return null;

  // Prefer a date near the word EXPIR(Y/ES/ATION); otherwise take the last
  // date on the document, which registration expiry tends to be.
  const expiryIdx = upper.indexOf("EXPIR");
  let chosen = dates[dates.length - 1];
  if (expiryIdx !== -1) {
    let closest = null;
    let closestDist = Infinity;
    for (const d of dates) {
      const dist = Math.abs(d.index - expiryIdx);
      if (dist < closestDist) {
        closest = d;
        closestDist = dist;
      }
    }
    if (closest) chosen = closest;
  }

  let [, a, b, year] = chosen;
  if (year.length === 2) year = `20${year}`;
  // Philippine documents are usually MM/DD/YYYY; treat the first number as
  // the month when it's plausible (<=12), otherwise assume DD/MM/YYYY.
  const month = Number(a) <= 12 ? a : b;
  const day = Number(a) <= 12 ? b : a;
  const mm = month.padStart(2, "0");
  const dd = day.padStart(2, "0");
  if (Number(mm) < 1 || Number(mm) > 12 || Number(dd) < 1 || Number(dd) > 31) {
    return null;
  }
  return `${year}-${mm}-${dd}`;
}

function titleCase(s) {
  return s
    .toLowerCase()
    .replace(/\b\w/g, (c) => c.toUpperCase());
}
