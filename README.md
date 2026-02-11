# PugPS

**Unleash Pug templates in PowerShell. A versatile CLI for HTML pipelines and a loyal View Engine for your Pode Server projects. 🐾**

PugPS is a PowerShell-native implementation of the Pug (formerly Jade) templating engine. It allows you to write clean, indented templates and render them into HTML using PowerShell logic, variables, and functions (JavaScript logic is not supported).

---

## 🚀 Usage in Pode

To use PugPS as your view engine in a [Pode](https://badgerati.github.io/Pode/) server, import the module and initialize the engine within your `Start-PodeServer` block.

```powershell
Start-PodeServer {
    # Import the view engine module
    Import-Module .\PugPS\pode-pug-engine
    
    # Configure the engine
    Set-PodeViewEnginePug -Extension 'pode.pug' -ErrorOutput 'text'
}
```

### `Set-PodeViewEnginePug` Parameters

| Parameter | Type | Req | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| **-Extension** | `string` | Yes | - | The default file extension to target (e.g., `pode.pug`). |
| **-BaseDir** | `string` | No | `""` | The root directory used to resolve absolute include/extend paths (starting with `/` or `\`). |
| **-Filters** | `sb\|string` | No | `$null` | The path to a `.ps1` filters file or a scriptblock containing filter functions. |
| **-Properties** | `bool` | No | `$true` | When `$true` (default), boolean attributes render as `attr`. When `$false`, `attr='attr'`. |
| **-VoidTagsSelfClosing** | `bool` | No | `$false` | When `$true`, standard void tags (like `img`, `br`) render as `<img />`. |
| **-ContainerTagsSelfClosing** | `bool` | No | `$false` | When `$true`, empty container tags (like `div`) render as `<div />`. |
| **-KebabCaseHTML** | `bool` | No | `$true` | When `$true`, `CamelCase` tags in PUG are converted to `kebab-case`. |
| **-ErrorOutput** | `string` | No | `'rethrow'` | `'text'` returns HTML error; `'rethrow'` triggers the Pode error page. |
| **-ErrorContextRange** | `int` | No | `2` | Number of context lines to show before and after the error line. |

---

## 💻 Usage as a CLI Tool

Use `Invoke-PUG` for automation, build pipelines, or one-off conversions.

```powershell
# Example 1: Convert a file with data and external filters
Invoke-PUG -Path .\test.pug -Data @{
    Title = "Pug PowerShell"
    Users = @(@{ Name = "Alice"; Role = "Admin" })
} -Filters .\helper.ps1

# Example 2: Pipe content directly with a scriptblock filter
@"
div
    :MyFilter
        Content
"@ | Invoke-PUG -Filters {
    Function MyFilter { 
        param([Parameter(ValueFromPipeline=$true)]$text) 
        "<b>$text</b>" 
    }
}
```

### `Invoke-PUG` Parameters

| Parameter | Type | Req | Set | Default | Description |
| :--- | :--- | :---: | :--- | :--- | :--- |
| **-Path** | `string` | Yes | Path | - | The path to the Pug template file. |
| **-InputContent** | `string[]` | Yes | Cont | - | The raw Pug template content (supports pipeline input). |
| **-Data** | `hashtable` | No | Both | `@{}` | The data passed to the template as `$data`. |
| **-Filters** | `sb\|string` | No | Both | `$null` | Path to filters file (ps1) or a scriptblock with filter functions. |
| **-Extension** | `string` | No | Both | `'pug'` | The default file extension to use for included files. |
| **-BaseDir** | `string` | No | Both | `""` | Root directory used to resolve absolute include/extend paths. |
| **-Properties** | `bool` | No | Both | `$true` | If `$true`, boolean attributes render as `attr`. |
| **-VoidTagsSelfClosing** | `bool` | No | Both | `$false` | If `$true`, void tags render with a self-closing slash. |
| **-ContainerTagsSelfClosing** | `bool` | No | Both | `$false` | If `$true`, empty container tags render as self-closing. |
| **-KebabCaseHTML** | `bool` | No | Both | `$true` | If `$true`, converts `CamelCase` tags to `kebab-case`. |
| **-ErrorContextRange** | `int` | No | Both | `2` | Context lines to show before/after error line. |

---

## 📝 Syntax Notes & Examples

### 1. PowerShell Control Flow
PugPS supports standard PowerShell logic using the `-` prefix.

```pug
- Foreach ($u in $data.Users)
    li= $u.Name

- If ($a -eq $true)
    li TRUE
- ElseIf ($a -eq $false)
    li FALSE
- Else
    li Unknown

- Switch ($data.Status)
    - "active"
        li User is Active
    - "disabled"
        li User is Locked
    - default
        li Status Unknown
```

#### NOTE: PugJS's Case, Conditionals, Iteration
- these can be done with `- Foreach`, `- If`, `- For` ... while keeping the powershell syntax (the PugJS specific implementation is not supported)
    - https://pugjs.org/language/case.html
    - https://pugjs.org/language/conditionals.html
    - https://pugjs.org/language/iteration.html



### 2. Classes and Styles
PugPS handles PowerShell collections intelligently for clean attribute management.

*   **Classes from Array:** Simple list output.
    ```pug
    - $classes = "btn", "btn-primary"
    button(class=$classes) // <button class="btn btn-primary">
    ```
*   **Classes from Object:** Keys mapped to `$true` are included; `$false` are omitted.
    ```pug
    - $classesObj = @{ active = $true; hidden = $false }
    div(class=$classesObj) // <div class="active">
    ```
*   **Styles from Object:** Keys in `camelCase` are automatically converted to `kebab-case`.
    ```pug
    - $styles = @{ backgroundColor = "red"; borderRadius = "5px" }
    div(style=$styles) // <div style="background-color:red;border-radius:5px">
    ```

### 3. Variables & Interpolation
*   **Attribute Values:** These are PowerShell expressions. Double quotes `" "` expand variables; single quotes `' '` do not.
*   **Content Interpolation:** Use `$( $var )` or `${ $var }` for raw content, and `#( $var )` or `#{ $var }` for escpaed HTML content. Preferred: use `$()` and `#()`.
*   **Escaping:** To escape a dollar sign in content, use `\$` or `` `$ ``. (`\` and `` ` `` can be escaped as well.)

#### Examples
- `attr='$a'`  var will not be parsed (singe quotes),
- `attr="$a"`  var will be parsed (double quotes),
- `$attr=$a`   var will be parsed (no quotes).

#### Note: Attributes with Code
For `body(class=$authenticated ? 'authed' : 'anon' ...)` and alike, you should use `body(class=$($authenticated ? 'authed' : 'anon') ...)` - wrapping the logic in `$()`

### 4. Filters
Filters trigger standard PowerShell functions. The nested content is passed via the pipeline. Params are used by their names.

```pug
:MyFilter(param="value")
    Content here is passed to the function
```

#### Filter
To access the pipeline value use `[Parameter(ValueFromPipeline=$true)]$text` (Conntent is passed as one single string, there is no need to collect lines)


```ps1
Function TestFN {
    param(
        $title,
        [Parameter(ValueFromPipeline=$true)]$text
    )

    "<div>" $title + '<br>' +  ($text ? $text : "-- no text --") + "<div>"
}
```

A filter can also be created inline in within the Pug (using `- Function TestFN{...}`)


### 5. Doctypes & XML
*   **Shortcuts:** `5` (HTML5), `smil1`, `smil2`, ... and for the PuJS default [ones look them up here](https://pugjs.org/language/doctype.html)
*   **Casing:** When using the XML doctype, `KebabCaseHTML` is automatically disabled to preserve XML casing.
*   **XML Mode:** For XML types (plist, svg1.1, smil1, smil2, etc.), always include `doctype xml` first.

Example:
```pug
doctype xml
doctype plist
plist(version="1.0")
  dict
    ...
```
A specific doctype for SVG Tiny 1.1 and 1.2 is not recomended. Only use: `doctype xml`


### 6. Includes & Mixins & Template Inheritance (Extends)
Are supported as defined by PugJS.

- https://pugjs.org/language/includes.html
- https://pugjs.org/language/mixins.html
- https://pugjs.org/language/inheritance.html


---

## ⚙️ Manual Transpilation

If you need to generate the PowerShell script representation of a Pug file without immediately rendering it, use `Convert-PugToPowerShell`.

```powershell
. .\PugPS\parser.ps1
$psCode = Convert-PugToPowerShell -Path "template.pug" -KebabCaseHTML $true
```

### `Convert-PugToPowerShell` Parameters
| Parameter | Type | Req | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| **-Path** | `string` | No* | - | Path to file (Mandatory if not using pipeline). |
| **-Extension** | `string` | No | `'pug'` | Extension for included files. |
| **-BaseDir** | `string` | No | `""` | Root directory for absolute paths. |
| **-Properties** | `bool` | No | `$true` | Render boolean attributes as `attr`. |
| **-VoidTagsSelfClosing** | `bool` | No | `$false` | Render void tags with `/`. |
| **-ContainerTagsSelfClosing** | `bool` | No | `$false` | Render empty containers with `/`. |
| **-KebabCaseHTML** | `bool` | No | `$true` | Convert `CamelCase` tags to `kebab-case`. |
| **-ErrorContextRange** | `int` | No | `2` | Error context line count. |

---

## 📦 Installation

```powershell
git clone https://github.com/BananaAcid/PugPS.git
```
