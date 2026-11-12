// Katalogkopie des Collectors im Ausgabeordner; fehlende Preise bleiben null.
let
    Json      = Json.Document(File.Contents(DatenOrdner & "lizenzkatalog.json")),
    Liste     = Json[produkte],
    Tabelle   = Table.FromRecords(Liste, null, MissingField.UseNull),
    Spalten   = Table.SelectColumns(Tabelle, {"produktId","produkt","produktfamilie","abrechnungsart","einheit","preisbasis",
                   "kapazitaetJeEinheit","listenpreis","kundenpreis","waehrung","gueltigAb","gueltigBis","datenquelle","aktiv"}, MissingField.UseNull),
    Eindeutig = if Table.RowCount(Spalten) = List.Count(List.Distinct(Spalten[produktId], Comparer.OrdinalIgnoreCase))
                   and List.AllTrue(List.Transform(Spalten[produktId], each Value.Is(_, type text) and Text.Trim(_) <> ""))
                then Spalten else error "produktId muss im Lizenzkatalog eindeutig und nicht leer sein.",
    Zahl      = (v as any) as nullable number =>
                   if v = null or v = "[prüfen]" then null
                   else if not Value.Is(v, type number) then error "Katalogpreise müssen Zahlen oder [prüfen] sein."
                   else if Number.IsNaN(v) or v = #infinity or v = -#infinity or v < 0 then error "Ungültiger Katalogpreis."
                   else v,
    Preise    = Table.TransformColumns(Eindeutig, {
                   {"listenpreis", each Zahl(_), type nullable number},
                   {"kundenpreis", each Zahl(_), type nullable number},
                   {"kapazitaetJeEinheit", each let n = Zahl(_) in if n = 0 then error "Kapazität muss positiv sein." else n, type nullable number}}),
    Daten     = Table.TransformColumnTypes(Preise, {{"gueltigAb", type date}, {"gueltigBis", type date}}),
    Standard  = Table.AddColumn(Daten, "waehrungStandard", each Json[waehrungStandard], type text)
in
    Standard
