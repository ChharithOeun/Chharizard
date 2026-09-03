; ============================================================================
; lib/json.ahk  —  minimal JSON encoder/decoder for AHK v2.
;
; AutoHotkey v2 has no built-in JSON. This is a small self-contained
; implementation. For heavier lifting later we can swap in JXON.
; Handles: objects (Map), arrays (Array), strings, numbers, true/false/null.
; ============================================================================

class JSON {
    ; --- Stringify -----------------------------------------------------------
    static Stringify(value, indent := "") {
        return JSON._stringify(value, indent, "")
    }

    static _stringify(v, indent, curIndent) {
        if (v = "" && Type(v) = "String")
            return '""'
        t := Type(v)
        if (t = "String")   return '"' . JSON._escape(v) . '"'
        if (t = "Integer" || t = "Float") return String(v)
        if (t = "Array") {
            if (v.Length = 0) return "[]"
            newIndent := curIndent . indent
            parts := []
            for item in v
                parts.Push((indent ? newIndent : "") . JSON._stringify(item, indent, newIndent))
            sep := indent ? ",`n" : ","
            open := indent ? "[`n" : "["
            close := indent ? "`n" . curIndent . "]" : "]"
            joined := ""
            for i, p in parts
                joined .= (i > 1 ? sep : "") . p
            return open . joined . close
        }
        if (t = "Map" || t = "Object") {
            keys := []
            if (t = "Map") {
                for k, _ in v
                    keys.Push(k)
            } else {
                for k, _ in v.OwnProps()
                    keys.Push(k)
            }
            if (keys.Length = 0) return "{}"
            newIndent := curIndent . indent
            parts := []
            for k in keys {
                val := (t = "Map") ? v[k] : v.%k%
                keyStr := '"' . JSON._escape(String(k)) . '"'
                valStr := JSON._stringify(val, indent, newIndent)
                parts.Push((indent ? newIndent : "") . keyStr . ":" . (indent ? " " : "") . valStr)
            }
            sep := indent ? ",`n" : ","
            open := indent ? "{`n" : "{"
            close := indent ? "`n" . curIndent . "}" : "}"
            joined := ""
            for i, p in parts
                joined .= (i > 1 ? sep : "") . p
            return open . joined . close
        }
        return "null"
    }

    static _escape(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        return s
    }

    ; --- Parse ---------------------------------------------------------------
    static Parse(text) {
        pos := [1]
        return JSON._parseValue(text, pos)
    }

    static _skipWs(text, pos) {
        while (pos[1] <= StrLen(text)) {
            c := SubStr(text, pos[1], 1)
            if (c = " " || c = "`t" || c = "`n" || c = "`r")
                pos[1]++
            else
                break
        }
    }

    static _parseValue(text, pos) {
        JSON._skipWs(text, pos)
        c := SubStr(text, pos[1], 1)
        if (c = "{") return JSON._parseObject(text, pos)
        if (c = "[") return JSON._parseArray(text, pos)
        if (c = '"') return JSON._parseString(text, pos)
        if (c = "t" || c = "f") return JSON._parseBool(text, pos)
        if (c = "n") return JSON._parseNull(text, pos)
        return JSON._parseNumber(text, pos)
    }

    static _parseObject(text, pos) {
        obj := Map()
        pos[1]++ ; consume {
        JSON._skipWs(text, pos)
        if (SubStr(text, pos[1], 1) = "}") {
            pos[1]++
            return obj
        }
        loop {
            JSON._skipWs(text, pos)
            key := JSON._parseString(text, pos)
            JSON._skipWs(text, pos)
            pos[1]++ ; consume :
            val := JSON._parseValue(text, pos)
            obj[key] := val
            JSON._skipWs(text, pos)
            c := SubStr(text, pos[1], 1)
            pos[1]++
            if (c = "}") break
        }
        return obj
    }

    static _parseArray(text, pos) {
        arr := []
        pos[1]++ ; consume [
        JSON._skipWs(text, pos)
        if (SubStr(text, pos[1], 1) = "]") {
            pos[1]++
            return arr
        }
        loop {
            val := JSON._parseValue(text, pos)
            arr.Push(val)
            JSON._skipWs(text, pos)
            c := SubStr(text, pos[1], 1)
            pos[1]++
            if (c = "]") break
        }
        return arr
    }

    static _parseString(text, pos) {
        pos[1]++ ; consume opening "
        s := ""
        while (pos[1] <= StrLen(text)) {
            c := SubStr(text, pos[1], 1)
            pos[1]++
            if (c = '"') return s
            if (c = "\") {
                esc := SubStr(text, pos[1], 1)
                pos[1]++
                if      (esc = "n")  s .= "`n"
                else if (esc = "r")  s .= "`r"
                else if (esc = "t")  s .= "`t"
                else if (esc = '"')  s .= '"'
                else if (esc = "\")  s .= "\"
                else if (esc = "/")  s .= "/"
                else                 s .= esc
            } else s .= c
        }
        return s
    }

    static _parseNumber(text, pos) {
        start := pos[1]
        while (pos[1] <= StrLen(text)) {
            c := SubStr(text, pos[1], 1)
            if (c ~= "[\d\.\-\+eE]")
                pos[1]++
            else break
        }
        n := SubStr(text, start, pos[1] - start)
        return InStr(n, ".") || InStr(n, "e") || InStr(n, "E") ? Number(n) : Integer(n)
    }

    static _parseBool(text, pos) {
        if (SubStr(text, pos[1], 4) = "true") { pos[1] += 4; return true }
        if (SubStr(text, pos[1], 5) = "false") { pos[1] += 5; return false }
        return false
    }

    static _parseNull(text, pos) {
        if (SubStr(text, pos[1], 4) = "null") { pos[1] += 4; return "" }
        return ""
    }
}
