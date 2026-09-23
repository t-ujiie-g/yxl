///|
/// Functions Excel added after the file format was fixed, which the file stores
/// as `_xlfn.NAME` (#96). Any other name passes through untouched either way.
let future_functions : Array[String] = [
  "ACOT", "ACOTH", "AGGREGATE", "ARABIC", "ARRAYTOTEXT", "BASE", "BETA.DIST", "BETA.INV",
  "BINOM.DIST", "BINOM.DIST.RANGE", "BINOM.INV", "BITAND", "BITLSHIFT", "BITOR",
  "BITRSHIFT", "BITXOR", "BYCOL", "BYROW", "CEILING.MATH", "CEILING.PRECISE", "CHISQ.DIST",
  "CHISQ.DIST.RT", "CHISQ.INV", "CHISQ.INV.RT", "CHISQ.TEST", "CHOOSECOLS", "CHOOSEROWS",
  "COMBINA", "CONCAT", "CONFIDENCE.NORM", "CONFIDENCE.T", "COT", "COTH", "COVARIANCE.P",
  "COVARIANCE.S", "CSC", "CSCH", "DAYS", "DECIMAL", "DROP", "ENCODEURL", "ERF.PRECISE",
  "ERFC.PRECISE", "EXPAND", "EXPON.DIST", "F.DIST", "F.DIST.RT", "F.INV", "F.INV.RT",
  "F.TEST", "FILTER", "FILTERXML", "FLOOR.MATH", "FLOOR.PRECISE", "FORECAST.ETS",
  "FORECAST.ETS.CONFINT", "FORECAST.ETS.SEASONALITY", "FORECAST.ETS.STAT", "FORECAST.LINEAR",
  "FORMULATEXT", "GAMMA", "GAMMA.DIST", "GAMMA.INV", "GAMMALN.PRECISE", "GAUSS",
  "HSTACK", "HYPGEOM.DIST", "IFNA", "IFS", "IMCOSH", "IMCOT", "IMCSC", "IMCSCH",
  "IMSEC", "IMSECH", "IMSINH", "IMTAN", "ISFORMULA", "ISOMITTED", "ISOWEEKNUM", "LAMBDA",
  "LET", "LOGNORM.DIST", "LOGNORM.INV", "MAKEARRAY", "MAP", "MAXIFS", "MINIFS", "MODE.MULT",
  "MODE.SNGL", "MUNIT", "NEGBINOM.DIST", "NETWORKDAYS.INTL", "NORM.DIST", "NORM.INV",
  "NORM.S.DIST", "NORM.S.INV", "NUMBERVALUE", "PDURATION", "PERCENTILE.EXC", "PERCENTILE.INC",
  "PERCENTRANK.EXC", "PERCENTRANK.INC", "PERMUTATIONA", "PHI", "POISSON.DIST", "QUARTILE.EXC",
  "QUARTILE.INC", "RANDARRAY", "RANK.AVG", "RANK.EQ", "REDUCE", "RRI", "SCAN", "SEC",
  "SECH", "SEQUENCE", "SHEET", "SHEETS", "SKEW.P", "SORT", "SORTBY", "STDEV.P", "STDEV.S",
  "STOCKHISTORY", "SWITCH", "T.DIST", "T.DIST.2T", "T.DIST.RT", "T.INV", "T.INV.2T",
  "T.TEST", "TAKE", "TEXTAFTER", "TEXTBEFORE", "TEXTJOIN", "TEXTSPLIT", "TOCOL",
  "TOROW", "UNICHAR", "UNICODE", "UNIQUE", "VALUETOTEXT", "VAR.P", "VAR.S", "VSTACK",
  "WEBSERVICE", "WEIBULL.DIST", "WORKDAY.INTL", "WRAPCOLS", "WRAPROWS", "XLOOKUP",
  "XMATCH", "XOR", "Z.TEST",
]

///|
/// The two a worksheet function stores under a second prefix, `_xlfn._xlws.`.
let worksheet_functions : Array[String] = ["FILTER", "SORT"]

///|
const XLFN : String = "_XLFN."

///|
const XLWS : String = "_XLWS."

///|
/// A formula as the file stores it: every function Excel added later carries
/// the `_xlfn.` prefix it is read by (#96). A name already prefixed stays so.
pub fn to_file_formula(formula : String) -> String {
  map_function_names(formula, name => {
    let upper = name.to_upper()
    guard future_functions.contains(upper) else { return name }
    if worksheet_functions.contains(upper) {
      "_xlfn._xlws.\{upper}"
    } else {
      "_xlfn.\{upper}"
    }
  })
}

///|
/// A formula as a spec writes it: the inverse of `to_file_formula`, so text
/// read from a file shows each function the way Excel's formula bar does.
pub fn from_file_formula(formula : String) -> String {
  map_function_names(formula, name => {
    let upper = name.to_upper()
    guard upper.has_prefix(XLFN) else { return name }
    let bare = upper[XLFN.length():].to_owned()
    let bare = if bare.has_prefix(XLWS) {
      bare[XLWS.length():].to_owned()
    } else {
      bare
    }
    if future_functions.contains(bare) {
      bare
    } else {
      name
    }
  })
}

///|
/// Rewrite each function name — a name followed by `(` — through `rename`,
/// leaving string literals and quoted sheet names as written.
fn map_function_names(formula : String, rename : (String) -> String) -> String {
  let chars = formula.to_array()
  let out = StringBuilder()
  let is_name_char = (ch : Char) => {
    ch.is_ascii_alphabetic() ||
    ch.is_ascii_digit() ||
    ch == '_' ||
    ch == '.' ||
    !ch.is_ascii()
  }
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '"' || ch == '\'' {
      let mut end = i + 1
      while end < chars.length() && chars[end] != ch {
        end += 1
      }
      let stop = if end < chars.length() { end + 1 } else { end }
      out.write_string(String::from_array(chars[i:stop]))
      i = stop
      continue
    }
    if is_name_char(ch) {
      let mut end = i
      while end < chars.length() && is_name_char(chars[end]) {
        end += 1
      }
      let name = String::from_array(chars[i:end])
      let called = end < chars.length() && chars[end] == '('
      out.write_string(if called { rename(name) } else { name })
      i = end
      continue
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}
