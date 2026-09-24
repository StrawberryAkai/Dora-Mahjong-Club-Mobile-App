<#
  Provision or reset one Dora administrator.

  This script intentionally accepts every secret through environment variables
  only.  It never writes credentials to a file or prints request bodies.  Run
  it from a trusted machine after the migration has been reviewed and applied.

  Required environment variables:
    SUPABASE_URL
    SUPABASE_SERVICE_ROLE_KEY
    DORA_ADMIN_USERNAME
    DORA_ADMIN_PASSWORD

  Set DORA_ADMIN_RESET_PASSWORD to true, 1, or yes to reset an existing
  Auth user's password.  Without that flag an existing password is left alone.
#>

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-RequiredEnvironmentValue([string] $Name) {
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Missing required environment variable: $Name"
    }
    return $value
}

function Invoke-SupabaseRequest(
    [string] $Method,
    [string] $Uri,
    [hashtable] $Headers,
    [object] $Body = $null
) {
    $params = @{
        Method = $Method
        Uri = $Uri
        Headers = $Headers
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $params.ContentType = 'application/json'
        $params.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
    }
    return Invoke-RestMethod @params
}

try {
    $supabaseUrl = (Get-RequiredEnvironmentValue 'SUPABASE_URL').TrimEnd('/')
    $serviceRoleKey = Get-RequiredEnvironmentValue 'SUPABASE_SERVICE_ROLE_KEY'
    $username = (Get-RequiredEnvironmentValue 'DORA_ADMIN_USERNAME').Trim()
    $password = Get-RequiredEnvironmentValue 'DORA_ADMIN_PASSWORD'

    if ($username -cnotmatch '^[a-z0-9_-]{3,32}$') {
        throw 'DORA_ADMIN_USERNAME must match [a-z0-9_-]{3,32}'
    }
    if ($password.Length -lt 8) {
        throw 'DORA_ADMIN_PASSWORD must contain at least 8 characters'
    }
    $url = [Uri] $supabaseUrl
    if ($url.Scheme -ne 'https' -and $url.Host -notin @('localhost', '127.0.0.1', '::1')) {
        throw 'SUPABASE_URL must use HTTPS (localhost is allowed for local development)'
    }

    $headers = @{
        apikey = $serviceRoleKey
        Authorization = "Bearer $serviceRoleKey"
    }
    $email = "$username@admin.dora.invalid"
    $perPage = 1000
    $page = 1
    $existing = $null

    do {
        $usersResponse = Invoke-SupabaseRequest -Method 'GET' `
            -Uri "$supabaseUrl/auth/v1/admin/users?page=$page&per_page=$perPage" `
            -Headers $headers
        $users = @($usersResponse.users)
        $existing = $users | Where-Object { $_.email -and $_.email.ToLowerInvariant() -eq $email } | Select-Object -First 1
        if ($null -ne $existing -or $users.Count -lt $perPage) {
            break
        }
        $page++
    } while ($true)

    $resetFlag = [Environment]::GetEnvironmentVariable('DORA_ADMIN_RESET_PASSWORD')
    $resetPassword = $resetFlag -in @('1', 'true', 'TRUE', 'yes', 'YES')
    $createdNewUser = $false
    if ($null -eq $existing) {
        $authUser = Invoke-SupabaseRequest -Method 'POST' `
            -Uri "$supabaseUrl/auth/v1/admin/users" `
            -Headers $headers `
            -Body ([ordered]@{
                email = $email
                password = $password
                email_confirm = $true
                user_metadata = [ordered]@{ dora_admin_username = $username }
            })
        $createdNewUser = $true
    } elseif ($resetPassword) {
        $alreadyProvisioned = Invoke-SupabaseRequest -Method 'POST' `
            -Uri "$supabaseUrl/rest/v1/rpc/admin_identity_status" `
            -Headers $headers `
            -Body ([ordered]@{
                p_username = $username
                p_auth_user_id = [string] $existing.id
            })
        if ($alreadyProvisioned -ne $true -and $alreadyProvisioned -ne 'true') {
            throw 'An existing Auth account is not a provisioned Dora administrator; choose an unused username'
        }
       $authUser = Invoke-SupabaseRequest -Method 'PUT' `
            -Uri "$supabaseUrl/auth/v1/admin/users/$($existing.id)" `
            -Headers $headers `
            -Body ([ordered]@{
                password = $password
                email_confirm = $true
                user_metadata = [ordered]@{ dora_admin_username = $username }
            })
    } else {
        $alreadyProvisioned = Invoke-SupabaseRequest -Method 'POST' `
            -Uri "$supabaseUrl/rest/v1/rpc/admin_identity_status" `
            -Headers $headers `
            -Body ([ordered]@{
                p_username = $username
                p_auth_user_id = [string] $existing.id
            })
        if ($alreadyProvisioned -ne $true -and $alreadyProvisioned -ne 'true') {
            throw 'An existing Auth account is not a provisioned Dora administrator; choose an unused username'
        }
        $authUser = $existing
    }

    if ($null -eq $authUser -or [string]::IsNullOrWhiteSpace([string] $authUser.id)) {
        throw 'Supabase Auth did not return an administrator user id'
    }

    Invoke-SupabaseRequest -Method 'POST' `
        -Uri "$supabaseUrl/rest/v1/rpc/provision_admin" `
        -Headers $headers `
        -Body ([ordered]@{
            p_username = $username
            p_auth_user_id = [string] $authUser.id
            p_is_new_auth_user = $createdNewUser
        }) | Out-Null

    Write-Host "Dora administrator provisioned: $username (Auth id $($authUser.id))"
} catch {
    # Do not echo the exception body: Auth responses and request URLs can
    # contain sensitive details.  The operator can rerun with corrected env.
    Write-Error 'Administrator provisioning failed. Check the migration, Supabase URL, service role key, and environment variables.'
    exit 1
}
