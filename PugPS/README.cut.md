# PugPS

**Unleash Pug templates in PowerShell. A versatile CLI for HTML pipelines and a loyal View Engine for your Pode Server projects. 🐾**

PugPS is a PowerShell-native implementation of the Pug (formerly Jade) templating engine. It allows you to write clean, indented templates and render them into HTML using PowerShell logic, variables, and functions (JavaScript logic is not supported).

---

## 📦 Installation

```powershell
Install-Module -name PugPS
```

*Latest version:  https://github.com/BananaAcid/PugPS*

---

## ⭐ Examples and general documentation

The general [PugJS Language Reference](https://pugjs.org/language/attributes.html) applies. Powershell specific usage is below.

How does Pug look like? See: https://html-to-pug.com/

---

## 🚀 Usage in Pode

To use PugPS as your view engine in a [Pode](https://badgerati.github.io/Pode/) server, import the module and initialize the engine within your `Start-PodeServer` block.

```powershell
Start-PodeServer {
    # Import the view engine module
    Import-Module PugPS
    
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
Import-Module PugPS

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

| Parameter | Type | Req | Default | Description |
| :--- | :--- | :---: | :--- | :--- |
| **-Path** | `string` | Yes* | - | Path to Pug Template file (Mandatory if not using pipeline). |
| **-InputContent** | `string[]` | Yes* | - | The raw Pug template content (supports pipeline input). |
| **-Data** | `hashtable` | No | `@{}` | The data passed to the template as `$data`. |
| **-Filters** | `sb\|string` | No | `$null` | Path to filters file (ps1) or a scriptblock with filter functions. |
| **-Extension** | `string` | No | `'pug'` | The default file extension to use for included files. |
| **-BaseDir** | `string` | No | `""` | Root directory used to resolve absolute include/extend paths. |
| **-Properties** | `bool` | No | `$true` | If `$true`, boolean attributes render as `attr`. |
| **-VoidTagsSelfClosing** | `bool` | No | `$false` | If `$true`, void tags render with a self-closing slash. |
| **-ContainerTagsSelfClosing** | `bool` | No | `$false` | If `$true`, empty container tags render as self-closing. |
| **-KebabCaseHTML** | `bool` | No | `$true` | If `$true`, converts `CamelCase` tags to `kebab-case`. |
| **-ErrorContextRange** | `int` | No | `2` | Context lines to show before/after error line. |

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



---

> [!NOTE]
> The Complete Readme is here:
>
> https://github.com/BananaAcid/PugPS/blob/main/README.md