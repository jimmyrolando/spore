// Checks the syntax (sh -n, without running anything) of the shell scripts
// embedded in the QML and JavaScript files: the string or template after
// "sh", "-c", the `script:` properties (also `checkScript:` and the like),
// the `var …Script =` of the .js files and the scripts DrivesService passes
// to run(disk, …).
// A quote that closes too early (e.g. an apostrophe in a comment inside a
// single-quoted script) breaks the whole script with no error in the shell's
// log, and many of these scripts only run when something needs them.
// JavaScript interpolations (${...}) are replaced by a word.
//
// Usage: node tools/check-scripts.mjs   (exit code 1 if any script fails)
import { readFileSync, readdirSync } from "node:fs"
import { join, relative } from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

const root = fileURLToPath(new URL("..", import.meta.url))
const sources = /(?:"sh",\s*"-c",\s*|property string \w*[Ss]cript:\s*|var \w*[Ss]cript\s*=\s*|run\(disk,\s*)(?=[`"'])/g

// The text a JavaScript string or template starting at `i` evaluates to, or
// null if it never closes.
function literal(src, i) {
    const quote = src[i]
    let out = ""
    for (i++; i < src.length; i++) {
        const c = src[i]
        if (c === "\\") {
            const e = src[++i]
            out += e === "n" ? "\n" : e === "t" ? "\t" : e
            continue
        }
        if (c === quote) return out
        if (quote === "`" && c === "$" && src[i + 1] === "{") {
            let depth = 1
            for (i += 2; i < src.length && depth; i++) {
                if (src[i] === "{") depth++
                else if (src[i] === "}") depth--
            }
            i--
            out += "X"
            continue
        }
        out += c
    }
    return null
}

function* sourceFiles(dir) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const path = join(dir, entry.name)
        if (entry.isDirectory()) yield* sourceFiles(path)
        else if (/\.(qml|js)$/.test(entry.name)) yield path
    }
}

let checked = 0
let failed = 0
for (const dir of ["shell", "greeter", "video"]) {
    for (const file of sourceFiles(join(root, dir))) {
        const src = readFileSync(file, "utf8")
        for (const m of src.matchAll(sources)) {
            const where = `${relative(root, file)}:${src.slice(0, m.index).split("\n").length}`
            const script = literal(src, m.index + m[0].length)
            checked++
            if (script === null) {
                failed++
                console.log(`${where}: the string never closes`)
                continue
            }
            try {
                execFileSync("sh", ["-n", "-c", script], { stdio: "pipe" })
            } catch (e) {
                failed++
                console.log(`${where}: ${String(e.stderr).trim().split("\n")[0]}`)
            }
        }
    }
}
console.log(`${checked} scripts checked${failed ? `, ${failed} with errors` : ""}`)
process.exit(failed ? 1 : 0)
