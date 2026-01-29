import Foundation
import AppKit
import UniformTypeIdentifiers

/// Service for exporting usage data to CSV and XLSX formats.
enum ExportService {

    // MARK: - CSV Export

    /// Exports daily usage data to CSV format.
    static func exportToCSV(_ data: [DailyUsage]) -> String {
        var csv = "Date,Models,Input,Output,Cache Create,Cache Read,Total Tokens,Cost (USD)\n"

        for day in data.sorted(by: { $0.date < $1.date }) {
            let models = day.modelBreakdowns
                .map { Formatters.formatModelNameCLI($0.modelName) }
                .joined(separator: "; ")

            let row = [
                day.date,
                "\"\(models)\"",
                String(day.inputTokens),
                String(day.outputTokens),
                String(day.cacheCreationTokens),
                String(day.cacheReadTokens),
                String(day.totalTokens),
                String(format: "%.2f", day.totalCost)
            ].joined(separator: ",")

            csv += row + "\n"
        }

        // Add totals row
        let totalInput = data.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = data.reduce(0) { $0 + $1.outputTokens }
        let totalCacheCreate = data.reduce(0) { $0 + $1.cacheCreationTokens }
        let totalCacheRead = data.reduce(0) { $0 + $1.cacheReadTokens }
        let totalTokens = data.reduce(0) { $0 + $1.totalTokens }
        let totalCost = data.reduce(0) { $0 + $1.totalCost }

        let totalsRow = [
            "Total",
            "",
            String(totalInput),
            String(totalOutput),
            String(totalCacheCreate),
            String(totalCacheRead),
            String(totalTokens),
            String(format: "%.2f", totalCost)
        ].joined(separator: ",")

        csv += totalsRow + "\n"

        return csv
    }

    /// Saves CSV data to a file using a save panel.
    @MainActor
    static func saveCSV(_ data: [DailyUsage]) async -> Bool {
        let csv = exportToCSV(data)

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "claude-usage-\(Formatters.todayDateString()).csv"
        panel.title = "Export Usage Data"
        panel.message = "Choose a location to save the CSV file"

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow!)

        if response == .OK, let url = panel.url {
            do {
                try csv.write(to: url, atomically: true, encoding: .utf8)
                return true
            } catch {
                print("Failed to save CSV: \(error)")
                return false
            }
        }
        return false
    }

    // MARK: - XLSX Export

    /// Exports daily usage data to XLSX format.
    static func exportToXLSX(_ data: [DailyUsage]) -> Data? {
        let sortedData = data.sorted(by: { $0.date < $1.date })

        // Build worksheet XML
        var rows: [[String]] = []

        // Header row
        rows.append(["Date", "Models", "Input", "Output", "Cache Create", "Cache Read", "Total Tokens", "Cost (USD)"])

        // Data rows
        for day in sortedData {
            let models = day.modelBreakdowns
                .map { Formatters.formatModelNameCLI($0.modelName) }
                .joined(separator: "; ")

            rows.append([
                day.date,
                models,
                String(day.inputTokens),
                String(day.outputTokens),
                String(day.cacheCreationTokens),
                String(day.cacheReadTokens),
                String(day.totalTokens),
                String(format: "%.2f", day.totalCost)
            ])
        }

        // Totals row
        let totalInput = data.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = data.reduce(0) { $0 + $1.outputTokens }
        let totalCacheCreate = data.reduce(0) { $0 + $1.cacheCreationTokens }
        let totalCacheRead = data.reduce(0) { $0 + $1.cacheReadTokens }
        let totalTokens = data.reduce(0) { $0 + $1.totalTokens }
        let totalCost = data.reduce(0) { $0 + $1.totalCost }

        rows.append([
            "Total",
            "",
            String(totalInput),
            String(totalOutput),
            String(totalCacheCreate),
            String(totalCacheRead),
            String(totalTokens),
            String(format: "%.2f", totalCost)
        ])

        return createXLSXData(rows: rows)
    }

    /// Saves XLSX data to a file using a save panel.
    @MainActor
    static func saveXLSX(_ data: [DailyUsage]) async -> Bool {
        guard let xlsxData = exportToXLSX(data) else {
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "xlsx")!]
        panel.nameFieldStringValue = "claude-usage-\(Formatters.todayDateString()).xlsx"
        panel.title = "Export Usage Data"
        panel.message = "Choose a location to save the Excel file"

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.mainWindow!)

        if response == .OK, let url = panel.url {
            do {
                try xlsxData.write(to: url)
                return true
            } catch {
                print("Failed to save XLSX: \(error)")
                return false
            }
        }
        return false
    }

    // MARK: - XLSX Generation

    /// Creates XLSX data from rows of strings.
    private static func createXLSXData(rows: [[String]]) -> Data? {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Create directory structure
            let xlDir = tempDir.appendingPathComponent("xl")
            let worksheetsDir = xlDir.appendingPathComponent("worksheets")
            let relsDir = tempDir.appendingPathComponent("_rels")
            let xlRelsDir = xlDir.appendingPathComponent("_rels")

            try FileManager.default.createDirectory(at: worksheetsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: xlRelsDir, withIntermediateDirectories: true)

            // [Content_Types].xml
            let contentTypes = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
                <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
                <Default Extension="xml" ContentType="application/xml"/>
                <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
                <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
            </Types>
            """
            try contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

            // _rels/.rels
            let rels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
            </Relationships>
            """
            try rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

            // xl/workbook.xml
            let workbook = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
                <sheets>
                    <sheet name="Usage Data" sheetId="1" r:id="rId1"/>
                </sheets>
            </workbook>
            """
            try workbook.write(to: xlDir.appendingPathComponent("workbook.xml"), atomically: true, encoding: .utf8)

            // xl/_rels/workbook.xml.rels
            let workbookRels = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
            </Relationships>
            """
            try workbookRels.write(to: xlRelsDir.appendingPathComponent("workbook.xml.rels"), atomically: true, encoding: .utf8)

            // xl/worksheets/sheet1.xml
            let sheet = generateSheetXML(rows: rows)
            try sheet.write(to: worksheetsDir.appendingPathComponent("sheet1.xml"), atomically: true, encoding: .utf8)

            // Create ZIP archive
            let zipURL = tempDir.appendingPathComponent("output.xlsx")
            let success = createZipArchive(from: tempDir, to: zipURL, excluding: ["output.xlsx"])

            if success {
                let data = try Data(contentsOf: zipURL)
                try? FileManager.default.removeItem(at: tempDir)
                return data
            }

            try? FileManager.default.removeItem(at: tempDir)
            return nil
        } catch {
            print("Failed to create XLSX: \(error)")
            try? FileManager.default.removeItem(at: tempDir)
            return nil
        }
    }

    /// Generates the sheet1.xml content for the worksheet.
    private static func generateSheetXML(rows: [[String]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <sheetData>
        """

        for (rowIndex, row) in rows.enumerated() {
            let rowNum = rowIndex + 1
            xml += "<row r=\"\(rowNum)\">"

            for (colIndex, cell) in row.enumerated() {
                let colLetter = columnLetter(for: colIndex)
                let cellRef = "\(colLetter)\(rowNum)"
                let escapedValue = escapeXML(cell)

                // Check if it's a number
                if let _ = Double(cell) {
                    xml += "<c r=\"\(cellRef)\"><v>\(cell)</v></c>"
                } else {
                    xml += "<c r=\"\(cellRef)\" t=\"inlineStr\"><is><t>\(escapedValue)</t></is></c>"
                }
            }

            xml += "</row>"
        }

        xml += """
            </sheetData>
        </worksheet>
        """

        return xml
    }

    /// Converts a column index to Excel column letter (0 = A, 1 = B, etc.).
    private static func columnLetter(for index: Int) -> String {
        var result = ""
        var idx = index
        repeat {
            result = String(UnicodeScalar(65 + (idx % 26))!) + result
            idx = idx / 26 - 1
        } while idx >= 0
        return result
    }

    /// Escapes special XML characters.
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// Creates a ZIP archive from a directory.
    private static func createZipArchive(from sourceDir: URL, to destinationURL: URL, excluding: [String]) -> Bool {
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(
            at: sourceDir,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        // Use Process to run zip command (available on macOS)
        let process = Process()
        process.currentDirectoryURL = sourceDir
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", destinationURL.path, "."]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Failed to create ZIP: \(error)")
            return false
        }
    }
}
