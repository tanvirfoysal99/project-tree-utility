function Get-TemplatePreset {
    param([string]$Name)
    $preset=Get-TemplatePresetCore $Name
    if(-not $preset){return $null}
    $package=[ordered]@{name=$preset.Name;version='0.0.1';private=$true}
    switch($preset.Name){
        react-vite {
            $package.type='module'
            $package.engines=@{node='>=22.12.0'}
            $package.scripts=@{dev='vite';build='vite build';typecheck='tsc --noEmit';preview='vite preview'}
            $package.dependencies=@{react='^19.3.1';'react-dom'='^19.3.1'}
            $package.devDependencies=@{vite='^8.3.6';typescript='^7.0.2';'@types/react'='^19.3.0';'@types/react-dom'='^19.3.0'}
            $tsconfig=@{compilerOptions=@{target='ES2022';lib=@('ES2022','DOM','DOM.Iterable');module='ESNext';moduleResolution='Bundler';jsx='react-jsx';strict=$true;skipLibCheck=$true;esModuleInterop=$true;allowSyntheticDefaultImports=$true;noEmit=$true};include=@('src','vite.config.ts')}
            ($preset.Entries|Where-Object Path -eq 'tsconfig.json').Content=$tsconfig|ConvertTo-Json -Depth 10
            $preset.Entries+=[pscustomobject]@{Path='src/vite-env.d.ts';IsDir=$false;Content='/// <reference types="vite/client" />' + "`n"}
        }
        hono-worker {
            $package.type='module';$package.engines=@{node='>=22.12.0'}
            $package.scripts=@{dev='wrangler dev';build='wrangler deploy --dry-run';deploy='wrangler deploy';typecheck='tsc --noEmit'}
            $package.dependencies=@{hono='^4.13.16'}
            $package.devDependencies=@{wrangler='^4.158.0';typescript='^7.0.2'}
            $tsconfig=@{compilerOptions=@{target='ES2022';lib=@('ES2022','WebWorker');module='ESNext';moduleResolution='Bundler';strict=$true;skipLibCheck=$true;noEmit=$true};include=@('src')}
            ($preset.Entries|Where-Object Path -eq 'tsconfig.json').Content=$tsconfig|ConvertTo-Json -Depth 10
        }
        monorepo-pnpm {
            $package.engines=@{node='>=22.12.0'}
            $package.scripts=@{build='pnpm -r --if-present build';test='pnpm -r --if-present test'}
        }
    }
    ($preset.Entries|Where-Object Path -eq 'package.json').Content=$package|ConvertTo-Json -Depth 10
    $preset.Entries+= [pscustomobject]@{Path='README.md';IsDir=$false;Content=('# '+$preset.Name+"`n`nRequires Node.js 22.12 or newer.`n"+$(if($preset.Name -eq 'monorepo-pnpm'){"Install pnpm, run pnpm install, then add packages under apps/ and packages/.`n"}else{"Run npm install, npm run typecheck, and npm run build.`nRun npm run dev for local development.`n"}))}
    return $preset
}
