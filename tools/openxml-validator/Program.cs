// Reads a workbook the way Excel does before it draws anything: open the
// package, then check every part against the ECMA-376 schema and the Open XML
// SDK's semantic rules. A file that fails here is a file Excel greets with its
// repair dialog — the failure `yxl`'s own round-trip tests structurally cannot
// see, because they re-open the bytes with the library that wrote them and a
// writer cannot disagree with itself.
//
// Two streams, on purpose. Progress and the summary go to stdout, for a human
// reading a CI log. The per-file findings go to stderr, keyed by base name and
// sorted, so a caller can diff that stream against a committed baseline of the
// defects it already knows about — see `.github/scripts/validate-xlsx.sh`.
//
// Exit codes: 0 every file valid, 1 at least one invalid, 2 misuse.

using DocumentFormat.OpenXml;
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;

namespace YxlOpenXmlValidator;

public static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("usage: openxml-validator <file.xlsx>...");
            return 2;
        }

        List<string> invalid = [];
        foreach (var path in args)
        {
            if (!File.Exists(path))
            {
                Console.Error.WriteLine($"error: file not found: {path}");
                return 2;
            }

            var name = Path.GetFileName(path);
            if (Validate(path, name))
            {
                Console.WriteLine($"ok    {name}");
            }
            else
            {
                Console.WriteLine($"FAIL  {name}");
                invalid.Add(name);
            }
        }

        if (invalid.Count == 0)
        {
            Console.WriteLine($"{args.Length} workbook(s) valid");
            return 0;
        }

        Console.WriteLine(
            $"{invalid.Count} of {args.Length} workbook(s) would not open cleanly: "
                + string.Join(", ", invalid)
        );
        return 1;
    }

    private static bool Validate(string path, string name)
    {
        List<string> findings;
        try
        {
            using var doc = SpreadsheetDocument.Open(path, false);
            // Office2013 is the oldest version that knows every part yxl emits:
            // slicers arrived in 2010, and the 2007 validator reports them as
            // unknown rather than as wrong.
            var validator = new OpenXmlValidator(FileFormatVersions.Office2013);
            // Rendered here, inside the `using`: `ValidationErrorInfo.Path`
            // walks back to the part it came from and throws once the package
            // is closed, so an error carried out of this scope is unreadable.
            findings = [.. validator.Validate(doc).Select(Describe)];
        }
        catch (Exception ex)
        {
            // A package too broken to open at all — a missing part, a
            // relationship pointing nowhere, a corrupt archive.
            Console.Error.WriteLine(name);
            Console.Error.WriteLine($"  cannot open: {ex.GetType().Name}: {ex.Message}");
            return false;
        }

        if (findings.Count == 0)
        {
            return true;
        }

        // Sorted so the same defect prints in the same order run to run, which
        // is what lets the stream be compared against a stored one.
        findings.Sort(StringComparer.Ordinal);
        Console.Error.WriteLine(name);
        foreach (var finding in findings)
        {
            Console.Error.WriteLine(finding);
        }
        return false;
    }

    private static string Describe(ValidationErrorInfo error)
    {
        var id = string.IsNullOrWhiteSpace(error.Id) ? "<no-id>" : error.Id;
        var xpath = error.Path?.XPath ?? "<no-xpath>";
        return $"  {id} {xpath}{Environment.NewLine}    {error.Description}";
    }
}
