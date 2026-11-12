// Kanonische Maschinendaten aus facts.json; facts.csv ist nur für Excel bestimmt.
// JSON bewahrt unveränderte Schlüssel, Währungen, JSON-Zahlen und unbekannte Aktivität (null).
// Parameter DatenOrdner (Text, mit abschließendem \) verweist auf 06_Daten\out\.
let
    Json      = Json.Document(File.Contents(DatenOrdner & "facts.json")),
    Pflicht   = {"monat", "produktId", "fachbereich", "region", "menge", "kostenIst"},
    Liste     = if not Value.Is(Json, type list) then error "facts.json muss ein Array sein."
                else if List.AllTrue(List.Transform(Json, each Value.Is(_, type record) and Record.HasFields(_, Pflicht)))
                     then Json else error "facts.json: Datensätze oder Pflichtfelder ungültig.",
    Spalten   = List.Combine({Pflicht, {"agent", "umgebung", "quelle", "zugewiesen", "aktiv", "unlizenziert", "waehrung"}}),
    Tabelle   = Table.FromRecords(Liste, Spalten, MissingField.UseNull),
    Textwert  = (v as any) as nullable text =>
                   if v = null then null else if Value.Is(v, type text) then v
                   else error "Textfeld in facts.json enthält keinen Text.",
    Texte     = Table.TransformColumns(Tabelle, List.Transform(
                   {"monat", "produktId", "fachbereich", "region", "agent", "umgebung", "quelle", "waehrung"},
                   each {_, Textwert, type nullable text})),
    Schluessel = Table.TransformColumns(Texte, {{"produktId", each
                   if _ = null or Text.Trim(_) = "" then error "produktId fehlt in facts.json." else _, type text}}),
    // Niemals ungültige Werte als Nullkosten behandeln. Unbekannte Nutzerzahlen bleiben null.
    Zahl      = (v as any, optional ganz as nullable logical) as nullable number =>
        if v = null then null
        else if not Value.Is(v, type number) then error "Zahlen müssen in facts.json JSON-Zahlen sein."
        else if Number.IsNaN(v) or v = #infinity or v = -#infinity then error "Nicht endliche Zahl in facts.json."
        else if ganz = true and (v < 0 or Number.RoundDown(v) <> v) then error "Nutzerzahlen müssen nichtnegative ganze Zahlen sein."
        else v,
    Waehrungen = Table.TransformColumns(Schluessel, {{"waehrung", each
                   if _ = null or Text.Trim(_) = "" then null
                   else let w = Text.Upper(Text.Trim(_)) in
                       if Text.Length(w) = 3 and Text.Select(w, {"A".."Z"}) = w then w
                       else error "Ungültige Währung in facts.json.", type nullable text}}),
    Zahlen    = Table.TransformColumns(Waehrungen, {
                   {"menge", each let n = Zahl(_) in if n = null then error "menge fehlt in facts.json." else n, type number},
                   {"kostenIst", each Zahl(_), type nullable number},
                   {"zugewiesen", each Zahl(_, true), Int64.Type},
                   {"aktiv", each Zahl(_, true), Int64.Type},
                   {"unlizenziert", each Zahl(_, true), Int64.Type}}),
    Datum     = Table.AddColumn(Zahlen, "Datum", each
                   if [monat] = null then error "monat fehlt in facts.json." else
                   let m = [monat], d = Date.FromText(m & "-01", [Format = "yyyy-MM-dd", Culture = "en-US"])
                   in if Text.Length(m) = 7 and Date.ToText(d, "yyyy-MM", "en-US") = m then d
                      else error "monat muss JJJJ-MM sein.", type date)
in
    Datum
