function ConvertTo-CredentialTarget {
    param([string]$Target)
    $value=$Target.Trim() -replace '^git:',''
    if($value -notmatch '^[a-z]+://'){$value='https://'+$value}
    $uri=$null
    if(-not [Uri]::TryCreate($value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or -not $uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Credential target must be an HTTPS host or repository URL without user info, query, or fragment.'}
    $path=$uri.AbsolutePath.TrimEnd('/')
    return 'git:https://'+$uri.Authority.ToLowerInvariant()+$path
}

function Initialize-CredentialVault {
    if('PtuCredentialVault' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;
using System.Text;
public sealed class PtuCredentialRecord { public string Username; public string Secret; }
public static class PtuCredentialVault {
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct Credential {
        public uint Flags, Type;
        public string TargetName, Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist, AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias, UserName;
    }
    [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredWrite(ref Credential value, uint flags);
    [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredRead(string target,uint type,uint flags,out IntPtr value);
    [DllImport("advapi32.dll", EntryPoint="CredDeleteW", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CredDelete(string target,uint type,uint flags);
    [DllImport("advapi32.dll")] static extern void CredFree(IntPtr value);
    public static void Write(string target,string username,string secret) {
        byte[] bytes=Encoding.Unicode.GetBytes(secret);
        IntPtr blob=Marshal.AllocHGlobal(bytes.Length);
        try {
            Marshal.Copy(bytes,0,blob,bytes.Length);
            Credential value=new Credential { Type=1,TargetName=target,UserName=username,CredentialBlobSize=(uint)bytes.Length,CredentialBlob=blob,Persist=2 };
            if(!CredWrite(ref value,0))throw new Win32Exception(Marshal.GetLastWin32Error());
        } finally {
            for(int i=0;i<bytes.Length;i++)Marshal.WriteByte(blob,i,0);
            Array.Clear(bytes,0,bytes.Length);Marshal.FreeHGlobal(blob);
        }
    }
    public static PtuCredentialRecord Read(string target) {
        IntPtr pointer;
        if(!CredRead(target,1,0,out pointer)) { int error=Marshal.GetLastWin32Error();if(error==1168)return null;throw new Win32Exception(error); }
        try {
            Credential value=(Credential)Marshal.PtrToStructure(pointer,typeof(Credential));
            return new PtuCredentialRecord { Username=value.UserName,Secret=Marshal.PtrToStringUni(value.CredentialBlob,(int)value.CredentialBlobSize/2) };
        } finally { CredFree(pointer); }
    }
    public static void Delete(string target) {
        if(!CredDelete(target,1,0)) { int error=Marshal.GetLastWin32Error();if(error!=1168)throw new Win32Exception(error); }
    }
}
'@ | Out-Null
}

function Invoke-CredentialVault {
    param([ValidateSet('read','write','delete')][string]$Action,[string]$Target,[string]$Username='oauth2',[string]$Secret='')
    Initialize-CredentialVault
    $canonical=ConvertTo-CredentialTarget $Target
    switch($Action){
        read { return [PtuCredentialVault]::Read($canonical) }
        write { [PtuCredentialVault]::Write($canonical,$Username,$Secret) }
        delete { [PtuCredentialVault]::Delete($canonical) }
    }
}

function Get-TreeStoredCredential {
    param([string]$Target)
    $canonical=ConvertTo-CredentialTarget $Target
    $uri=[Uri]($canonical.Substring(4))
    $hostTarget='git:https://'+$uri.Authority.ToLowerInvariant()
    foreach($candidate in @($canonical,$hostTarget)|Select-Object -Unique){
        $record=Invoke-CredentialVault read $candidate
        if($record -and $record.Secret){return $record.Secret}
    }
    $payload="protocol=https`nhost=$($uri.Authority)`n"
    if($uri.AbsolutePath.Trim('/')){$payload+='path='+$uri.AbsolutePath.Trim('/')+"`n"}
    $payload+="`n"
    foreach($name in @('git-credential-manager','git-credential-manager-core','git')){
        $command=Get-Command $name -CommandType Application -ErrorAction SilentlyContinue
        if(-not $command){continue}
        $start=New-Object Diagnostics.ProcessStartInfo
        $start.FileName=$command.Source;$start.Arguments=$(if($name -eq 'git'){'credential fill'}else{'get'})
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $start.RedirectStandardInput=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
        $start.EnvironmentVariables['GCM_INTERACTIVE']='Never';$start.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
        $process=New-Object Diagnostics.Process;$process.StartInfo=$start
        try{
            $null=$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errorOutput=$process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write($payload);$process.StandardInput.Close()
            if(-not $process.WaitForExit(5000)){$process.Kill();continue}
            if($process.ExitCode -ne 0){continue}
            foreach($line in ($output.Result -split "`r?`n")){if($line.StartsWith('password=')){return $line.Substring(9)}}
        }catch{continue}finally{$process.Dispose()}
    }
    return ''
}
