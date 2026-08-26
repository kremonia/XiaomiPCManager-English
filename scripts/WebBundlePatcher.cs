// JS bundle patcher: replaces WHOLE string literals - and the static
// segments of template literals - that are dictionary keys. Multi-char keys
// are also replaced as fragments inside decoded literals so concatenation
// fragments translate; single-char keys never fragment (they corrupt
// neighbors like 上 inside 上海). A proper tokenizer (strings, templates,
// comments, regex literals) keeps quote pairing correct in minified code.
using System;
using System.Collections.Generic;
using System.Text;
using System.Web.Script.Serialization;

public class WebBundlePatcher
{
    private static bool IsCjk(char c)
    {
        return (c >= '\u2E80' && c <= '\u9FFF') || (c >= '\u3000' && c <= '\u303F') ||
               (c >= '\uF900' && c <= '\uFAFF') || (c >= '\uFF00' && c <= '\uFF64');
    }

    private static bool ContainsCjk(string s)
    {
        for (int i = 0; i < s.Length; i++) if (IsCjk(s[i])) return true;
        return false;
    }

    private static string Escape(string value, char quote)
    {
        var builder = new StringBuilder(value.Length + 16);
        foreach (char c in value)
        {
            int code = c;
            if (c == '\\') builder.Append("\\\\");
            else if (c == quote) { builder.Append('\\'); builder.Append(quote); }
            else if (c == '\n') builder.Append("\\n");
            else if (c == '\r') builder.Append("\\r");
            else if (c == '\t') builder.Append("\\t");
            else if (code < 0x20 || code == 0x7F || code > 0x7E) builder.Append("\\u" + code.ToString("x4"));
            else builder.Append(c);
        }
        return builder.ToString();
    }

    // A '/' starts a regex (rather than division) when the previous
    // significant character cannot end an expression operand.
    private static bool RegexAllowedAfter(char prev)
    {
        if (prev == '\0') return true;
        if (Char.IsLetterOrDigit(prev)) return false;
        if (prev == ')' || prev == ']' || prev == '}' || prev == '_' || prev == '$' ||
            prev == '"' || prev == '\'' || prev == '`') return false;
        return true;
    }

    private static int ParseHex(string source, int start, int digits)
    {
        int value = 0;
        for (int k = 0; k < digits; k++)
        {
            int digit = HexValue(source[start + k]);
            if (digit < 0) return -1;
            value = (value << 4) | digit;
        }
        return value;
    }

    private static int HexValue(char c)
    {
        if (c >= '0' && c <= '9') return c - '0';
        if (c >= 'a' && c <= 'f') return c - 'a' + 10;
        if (c >= 'A' && c <= 'F') return c - 'A' + 10;
        return -1;
    }

    private static string DecodeEscapes(string raw)
    {
        var builder = new StringBuilder(raw.Length);
        int i = 0;
        while (i < raw.Length)
        {
            char c = raw[i];
            if (c != '\\' || i + 1 >= raw.Length) { builder.Append(c); i++; continue; }
            char e = raw[i + 1];
            if (e == 'u' && i + 6 <= raw.Length)
            {
                int code = ParseHex(raw, i + 2, 4);
                if (code >= 0)
                {
                    i += 6;
                    if (code >= 0xD800 && code <= 0xDBFF && i + 6 <= raw.Length &&
                        raw[i] == '\\' && raw[i + 1] == 'u')
                    {
                        int low = ParseHex(raw, i + 2, 4);
                        if (low >= 0xDC00 && low <= 0xDFFF)
                        {
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
                            i += 6;
                        }
                    }
                    if (code >= 0x10000)
                    {
                        code -= 0x10000;
                        builder.Append((char)(0xD800 + (code >> 10)));
                        builder.Append((char)(0xDC00 + (code & 0x3FF)));
                    }
                    else builder.Append((char)code);
                    continue;
                }
            }
            if (e == 'x' && i + 4 <= raw.Length)
            {
                int code = ParseHex(raw, i + 2, 2);
                if (code >= 0) { builder.Append((char)code); i += 4; continue; }
            }
            switch (e)
            {
                case 'n': builder.Append('\n'); break;
                case 'r': builder.Append('\r'); break;
                case 't': builder.Append('\t'); break;
                case 'b': builder.Append('\b'); break;
                case 'f': builder.Append('\f'); break;
                case 'v': builder.Append('\v'); break;
                case '0': builder.Append('\0'); break;
                default: builder.Append('\\').Append(e); break;
            }
            i += 2;
        }
        return builder.ToString();
    }

    [ThreadStatic] private static string[] fragmentKeysAll;
    [ThreadStatic] private static string[] fragmentKeysMulti;
    [ThreadStatic] private static Dictionary<string, string> fragmentDictionary;

    // Fragment replacement inside a decoded literal: dictionary keys are
    // replaced longest-first. minLength 1 is used for ordinary literals and
    // templates; minLength 2 is used inside JSON payload strings, where
    // single-char keys would corrupt region names (上 inside 上海).
    private static string ReplaceFragments(string decoded, Dictionary<string, string> dictionary, int minLength)
    {
        if (!ReferenceEquals(fragmentDictionary, dictionary))
        {
            var all = new List<string>();
            var multi = new List<string>();
            foreach (var key in dictionary.Keys)
            {
                if (!ContainsCjk(key)) continue;
                all.Add(key);
                if (key.Length >= 2) multi.Add(key);
            }
            all.Sort((left, right) => right.Length.CompareTo(left.Length));
            multi.Sort((left, right) => right.Length.CompareTo(left.Length));
            fragmentKeysAll = all.ToArray();
            fragmentKeysMulti = multi.ToArray();
            fragmentDictionary = dictionary;
        }
        string[] keys = minLength <= 1 ? fragmentKeysAll : fragmentKeysMulti;
        string result = decoded;
        bool changed = false;
        foreach (string key in keys)
        {
            if (result.IndexOf(key, StringComparison.Ordinal) >= 0)
            {
                result = result.Replace(key, dictionary[key]);
                changed = true;
            }
        }
        return changed ? result : null;
    }

    // Inside JSON payload spans a multi-char key is replaced only at the start
    // of a CJK run (北京:北京 -> Beijing:Beijing, but 椭圆路径 stays whole
    // because 路径 is preceded by another CJK character).
    private static string ReplaceJsonRunKeys(string decoded, Dictionary<string, string> dictionary)
    {
        if (!ReferenceEquals(fragmentDictionary, dictionary)) ReplaceFragments(decoded, dictionary, 2);
        var builder = new StringBuilder(decoded.Length);
        int i = 0;
        bool changed = false;
        while (i < decoded.Length)
        {
            bool matched = false;
            if (i == 0 || !IsCjk(decoded[i - 1]))
            {
                foreach (string key in fragmentKeysMulti)
                {
                    if (decoded.IndexOf(key, i, StringComparison.Ordinal) == i)
                    {
                        builder.Append(dictionary[key]);
                        i += key.Length;
                        matched = true;
                        changed = true;
                        break;
                    }
                }
            }
            if (!matched) { builder.Append(decoded[i]); i++; }
        }
        return changed ? builder.ToString() : null;
    }

    // A literal that decodes to JSON (e.g. the region-code payload passed to
    // JSON.parse): translate each inner "..." span as an exact key first,
    // then as a leading multi-char key. Everything else is preserved byte for byte.
    private static string ReplaceJsonPayload(string rawContent, Dictionary<string, string> dictionary, ref int applied)
    {
        var result = new StringBuilder(rawContent.Length);
        bool changed = false;
        int i = 0;
        int length = rawContent.Length;
        while (i < length)
        {
            if (rawContent[i] != '"') { result.Append(rawContent[i]); i++; continue; }
            int start = i;
            i++;
            while (i < length)
            {
                if (rawContent[i] == '\\') { i += 2; continue; }
                if (rawContent[i] == '"') { i++; break; }
                i++;
            }
            string rawSpan = rawContent.Substring(start, i - start);
            string decodedSpan = DecodeEscapes(rawSpan.Substring(1, rawSpan.Length - 2));
            string translation;
            string rebuilt;
            if (dictionary.TryGetValue(decodedSpan, out translation))
            {
                result.Append('"').Append(Escape(translation, '"')).Append('"');
                changed = true;
            }
            else if (ContainsCjk(decodedSpan) &&
                     (rebuilt = ReplaceJsonRunKeys(decodedSpan, dictionary)) != null)
            {
                result.Append('"').Append(Escape(rebuilt, '"')).Append('"');
                changed = true;
            }
            else
            {
                result.Append(rawSpan);
            }
        }
        if (!changed) return null;
        applied++;
        return result.ToString();
    }

    private static void AppendTranslated(StringBuilder output, string rawSegment, char quote,
        Dictionary<string, string> dictionary, ref int applied, ref int keptChinese)
    {
        string decoded = DecodeEscapes(rawSegment);
        if (!ContainsCjk(decoded)) { output.Append(rawSegment); return; }
        string translation;
        string rebuilt;
        if (dictionary.TryGetValue(decoded, out translation))
        {
            output.Append(Escape(translation, quote));
            applied++;
        }
        else if (decoded.Length > 0 && (decoded[0] == '{' || decoded[0] == '[') &&
                 (rebuilt = ReplaceJsonPayload(rawSegment, dictionary, ref applied)) != null)
        {
            output.Append(rebuilt);
        }
        else if ((rebuilt = ReplaceFragments(decoded, dictionary, 1)) != null)
        {
            output.Append(Escape(rebuilt, quote));
            applied++;
        }
        else
        {
            keptChinese++;
            output.Append(rawSegment);
        }
    }

    // Structural validation of a patched bundle: every string literal and
    // template must terminate, every template ${...} expression must close,
    // and regex literals must not run to end of file. Returns null when the
    // structure is sound, or a description of the first anomaly.
    public static string Verify(string source)
    {
        int length = source.Length;
        int i = 0;
        char prev = '\0';
        while (i < length)
        {
            char c = source[i];
            if (Char.IsWhiteSpace(c)) { i++; continue; }
            if (c == '/' && i + 1 < length && source[i + 1] == '/')
            {
                int end = source.IndexOf('\n', i);
                i = end < 0 ? length : end;
                continue;
            }
            if (c == '/' && i + 1 < length && source[i + 1] == '*')
            {
                int end = source.IndexOf("*/", i, StringComparison.Ordinal);
                if (end < 0) return "unterminated block comment at " + i;
                i = end + 2;
                prev = ';';
                continue;
            }
            if (c == '"' || c == '\'')
            {
                char quote = c;
                i++;
                bool closed = false;
                while (i < length)
                {
                    if (source[i] == '\\') { i += 2; continue; }
                    if (source[i] == quote) { i++; closed = true; break; }
                    i++;
                }
                if (!closed) return "unterminated " + quote + " string at " + i;
                prev = quote;
                continue;
            }
            if (c == '`')
            {
                i++;
                bool closed = false;
                while (i < length)
                {
                    char d = source[i];
                    if (d == '\\') { i += 2; continue; }
                    if (d == '`') { i++; closed = true; break; }
                    if (d == '$' && i + 1 < length && source[i + 1] == '{')
                    {
                        i += 2;
                        int depth = 1;
                        while (i < length && depth > 0)
                        {
                            char e = source[i];
                            if (e == '\\') { i += 2; continue; }
                            if (e == '{') depth++;
                            else if (e == '}') { depth--; i++; continue; }
                            else if (e == '"' || e == '\'' || e == '`')
                            {
                                char inner = e;
                                i++;
                                bool innerClosed = false;
                                while (i < length)
                                {
                                    if (source[i] == '\\') { i += 2; continue; }
                                    if (source[i] == inner) { i++; innerClosed = true; break; }
                                    i++;
                                }
                                if (!innerClosed) return "unterminated string inside template expression at " + i;
                                continue;
                            }
                            i++;
                        }
                        if (depth > 0) return "unclosed ${ expression in template at " + i;
                        continue;
                    }
                    i++;
                }
                if (!closed) return "unterminated template literal at " + i;
                prev = '`';
                continue;
            }
            if (c == '/' && RegexAllowedAfter(prev))
            {
                i++;
                bool inClass = false;
                bool closed = false;
                while (i < length)
                {
                    char d = source[i];
                    if (d == '\\') { i += 2; continue; }
                    if (d == '[') inClass = true;
                    else if (d == ']') inClass = false;
                    else if (d == '/' && !inClass) { i++; closed = true; break; }
                    else if (d == '\n') break;
                    i++;
                }
                if (!closed) return "unterminated regex literal at " + i;
                prev = '/';
                continue;
            }
            prev = c;
            i++;
        }
        return null;
    }

    public static string Patch(string source, string jsonDictionary, out int applied, out int keptChinese)
    {
        var serializer = new JavaScriptSerializer();
        var raw = serializer.Deserialize<Dictionary<string, object>>(jsonDictionary);
        var dictionary = new Dictionary<string, string>(raw.Count);
        foreach (var entry in raw) dictionary[entry.Key] = entry.Value as string;

        var output = new StringBuilder(source.Length + 65536);
        applied = 0;
        keptChinese = 0;
        int length = source.Length;
        int i = 0;
        char prev = '\0';

        while (i < length)
        {
            char c = source[i];
            if (Char.IsWhiteSpace(c)) { output.Append(c); i++; continue; }

            if (c == '/' && i + 1 < length && source[i + 1] == '/')
            {
                int end = source.IndexOf('\n', i);
                if (end < 0) end = length;
                output.Append(source, i, end - i);
                i = end;
                continue;
            }
            if (c == '/' && i + 1 < length && source[i + 1] == '*')
            {
                int end = source.IndexOf("*/", i, StringComparison.Ordinal);
                end = end < 0 ? length : end + 2;
                output.Append(source, i, end - i);
                i = end;
                prev = ';';
                continue;
            }

            if (c == '"' || c == '\'')
            {
                char quote = c;
                int start = i;
                i++;
                bool closed = false;
                while (i < length)
                {
                    char d = source[i];
                    if (d == '\\') { i += 2; continue; }
                    if (d == quote) { i++; closed = true; break; }
                    i++;
                }
                if (closed)
                {
                    string rawContent = source.Substring(start + 1, i - start - 2);
                    output.Append(quote);
                    AppendTranslated(output, rawContent, quote, dictionary, ref applied, ref keptChinese);
                    output.Append(quote);
                }
                else
                {
                    output.Append(source, start, length - start);
                    i = length;
                }
                prev = quote;
                continue;
            }

            if (c == '`')
            {
                output.Append('`');
                i++;
                int segmentStart = i;
                bool closed = false;
                while (i < length)
                {
                    char d = source[i];
                    if (d == '\\') { i += 2; continue; }
                    if (d == '`')
                    {
                        AppendTranslated(output, source.Substring(segmentStart, i - segmentStart), '`',
                            dictionary, ref applied, ref keptChinese);
                        output.Append('`');
                        i++;
                        closed = true;
                        break;
                    }
                    if (d == '$' && i + 1 < length && source[i + 1] == '{')
                    {
                        AppendTranslated(output, source.Substring(segmentStart, i - segmentStart), '`',
                            dictionary, ref applied, ref keptChinese);
                        output.Append("${");
                        i += 2;
                        int depth = 1;
                        while (i < length && depth > 0)
                        {
                            char e = source[i];
                            if (e == '{') depth++;
                            else if (e == '}') depth--;
                            else if (e == '"' || e == '\'' || e == '`')
                            {
                                // Copy string/template content inside the
                                // expression verbatim - dropping it would
                                // unbalance the emitted quotes and corrupt
                                // the bundle.
                                char inner = e;
                                output.Append(e);
                                i++;
                                while (i < length)
                                {
                                    if (source[i] == '\\') { output.Append(source[i]); output.Append(i + 1 < length ? source[i + 1] : '\0'); i += 2; continue; }
                                    if (source[i] == inner) break;
                                    output.Append(source[i]);
                                    i++;
                                }
                            }
                            output.Append(e);
                            i++;
                        }
                        segmentStart = i;
                        continue;
                    }
                    i++;
                }
                if (!closed)
                {
                    AppendTranslated(output, source.Substring(segmentStart, length - segmentStart), '`',
                        dictionary, ref applied, ref keptChinese);
                    i = length;
                }
                prev = '`';
                continue;
            }

            if (c == '/' && RegexAllowedAfter(prev))
            {
                int start = i;
                i++;
                bool inClass = false;
                while (i < length)
                {
                    char d = source[i];
                    if (d == '\\') { i += 2; continue; }
                    if (d == '[') inClass = true;
                    else if (d == ']') inClass = false;
                    else if (d == '/' && !inClass)
                    {
                        i++;
                        while (i < length && Char.IsLetter(source[i])) i++;
                        break;
                    }
                    else if (d == '\n') break;
                    i++;
                }
                output.Append(source, start, i - start);
                prev = '/';
                continue;
            }

            output.Append(c);
            prev = c;
            i++;
        }

        return output.ToString();
    }
}
