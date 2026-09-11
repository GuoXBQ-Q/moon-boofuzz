///|
pub fn select_case(
  records : Array[CaseRecord],
  case_id : String,
) -> CaseRecord raise RecordError {
  guard !case_id.is_empty() else { raise Invalid("missing case identity") }
  let mut found : CaseRecord? = None
  for record in records {
    record.validate()
    if record.case_id == case_id {
      guard found is None else {
        raise Invalid("case identity is ambiguous across records")
      }
      found = Some(record)
    }
  }
  found.unwrap_or_else(() => raise Invalid("unknown case identity: " + case_id))
}
