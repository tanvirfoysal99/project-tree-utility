use crate::formats::{self, Entry};
use anyhow::{Result, bail};

fn file(path: &str, content: impl Into<String>) -> Entry {
    let mut entry = Entry::new(path, false);
    entry.content = Some(content.into());
    entry
}

pub fn preset(name: &str) -> Result<Vec<Entry>> {
    // Versions match the existing toolkit's preset manifests. Dependency installation
    // belongs to the generated application, never to scaffold itself.
    let package = match name {
        "react-vite" => {
            serde_json::json!({"name":"react-vite-app","version":"0.0.1","private":true,"type":"module","engines":{"node":">=22.12.0"},"scripts":{"dev":"vite","build":"vite build","typecheck":"tsc --noEmit","preview":"vite preview"},"dependencies":{"react":"^19.3.1","react-dom":"^19.3.1"},"devDependencies":{"vite":"^8.3.6","typescript":"^7.0.2","@types/react":"^19.3.0","@types/react-dom":"^19.3.0"}})
        }
        "hono-worker" => {
            serde_json::json!({"name":"hono-worker","version":"0.0.1","private":true,"type":"module","engines":{"node":">=22.12.0"},"scripts":{"dev":"wrangler dev","build":"wrangler deploy --dry-run","deploy":"wrangler deploy","typecheck":"tsc --noEmit"},"dependencies":{"hono":"^4.13.16"},"devDependencies":{"wrangler":"^4.158.0","typescript":"^7.0.2"}})
        }
        "monorepo-pnpm" => {
            serde_json::json!({"name":"monorepo-pnpm","version":"0.0.1","private":true,"engines":{"node":">=22.12.0"},"scripts":{"build":"pnpm -r --if-present build","test":"pnpm -r --if-present test"}})
        }
        _ => bail!("Unknown template: {name}"),
    };
    let mut entries = vec![
        file(
            "package.json",
            serde_json::to_string_pretty(&package)? + "\n",
        ),
        file(
            ".gitignore",
            "node_modules/\ndist/\nbuild/\n.env\n.wrangler/\n",
        ),
    ];
    match name {
        "react-vite" => {
            entries.extend([
                file("src/main.tsx", "import React from 'react';\nimport ReactDOM from 'react-dom/client';\nimport App from './App';\nimport './index.css';\n\nReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(<React.StrictMode><App /></React.StrictMode>);\n"),
                file("src/App.tsx", "export default function App() {\n  return <main>Hello from React Vite</main>;\n}\n"),
                file("src/index.css", "html, body, #root { margin: 0; min-height: 100%; }\nbody { font-family: system-ui, sans-serif; }\n"),
                file("src/vite-env.d.ts", "/// <reference types=\"vite/client\" />\n"),
                file("index.html", "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"UTF-8\" /><meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\" /><title>React Vite App</title></head><body><div id=\"root\"></div><script type=\"module\" src=\"/src/main.tsx\"></script></body></html>\n"),
                file("vite.config.ts", "import { defineConfig } from 'vite';\nexport default defineConfig({});\n"),
                file("tsconfig.json", serde_json::to_string_pretty(&serde_json::json!({"compilerOptions":{"target":"ES2022","lib":["ES2022","DOM","DOM.Iterable"],"module":"ESNext","moduleResolution":"Bundler","jsx":"react-jsx","strict":true,"skipLibCheck":true,"esModuleInterop":true,"allowSyntheticDefaultImports":true,"noEmit":true},"include":["src","vite.config.ts"]}))? + "\n"),
            ]);
        }
        "hono-worker" => {
            entries.extend([
                file("src/index.ts", "import { Hono } from 'hono';\nconst app = new Hono();\napp.get('/', (c) => c.text('Hello from Hono Worker'));\nexport default app;\n"),
                file("wrangler.toml", "name = \"hono-worker\"\nmain = \"src/index.ts\"\ncompatibility_date = \"2024-01-01\"\n"),
                file("tsconfig.json", serde_json::to_string_pretty(&serde_json::json!({"compilerOptions":{"target":"ES2022","lib":["ES2022","WebWorker"],"module":"ESNext","moduleResolution":"Bundler","strict":true,"skipLibCheck":true,"noEmit":true},"include":["src"]}))? + "\n"),
            ]);
        }
        "monorepo-pnpm" => entries.extend([
            Entry::new("apps/web", true),
            Entry::new("packages/ui", true),
            file(
                "pnpm-workspace.yaml",
                "packages:\n  - apps/*\n  - packages/*\n",
            ),
        ]),
        _ => unreachable!(),
    }
    entries.push(file("README.md", format!("# {name}\n\nRequires Node.js 22.12 or newer.\n\n{}\n", if name == "monorepo-pnpm" { "Install pnpm, run `pnpm install`, then add packages under `apps/` and `packages/`." } else { "Run `npm install`, `npm run typecheck`, and `npm run build`.\nUse `npm run dev` for local development." })));
    formats::normalize(entries)
}

pub fn stub(path: &str, template: Option<&str>) -> Result<String> {
    if let Some(template) = template
        && let Some(entry) = preset(template)?.into_iter().find(|e| e.path == path)
    {
        return Ok(entry.content.unwrap_or_default());
    }
    Ok(String::new())
}
