// KonfigOrdner verweist auf 02_Konfiguration\Beispiele\ (oder den eigenen Budgetordner).
// Budgetbeträge gelten in der waehrungStandard des Lizenzkatalogs für das ausgewertete Jahr.
let
    Json    = Json.Document(File.Contents(KonfigOrdner & "budget.json")),
    Tabelle = Record.ToTable(Json),
    Namen   = Table.RenameColumns(Tabelle, {{"Name", "Fachbereich"}, {"Value", "Betrag"}}),
    Typen   = Table.TransformColumns(Namen, {{"Betrag", each
                  if not Value.Is(_, type number) then error "Budgetbeträge müssen JSON-Zahlen sein."
                  else if Number.IsNaN(_) or _ = #infinity or _ = -#infinity or _ < 0 then error "Ungültiger Budgetbetrag."
                  else _, type number}})
in
    Typen
