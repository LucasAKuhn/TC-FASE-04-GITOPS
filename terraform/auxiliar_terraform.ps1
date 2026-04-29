# Terraform Automation Wrapper - ToggleMaster Project
# Versão interativa com captura de métricas e logs

$ErrorActionPreference = "Continue"

Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   AUTOMAÇÃO TERRAFORM - PROJETO TOGGLEMASTER" -ForegroundColor Cyan
Write-Host "   Gerenciamento de Ciclo de Vida de Infra"    -ForegroundColor DarkCyan
Write-Host "===============================================" -ForegroundColor Cyan

# Menu de Opções
Write-Host "`nO que você deseja executar?"
Write-Host "1. APPLY   - Provisionar/Atualizar infraestrutura"
Write-Host "2. DESTROY - Destruir toda a infraestrutura"
Write-Host "Q. SAIR    - Cancelar operação"
$choice = Read-Host "`nEscolha uma opção (1, 2 ou Q)"

# Lógica de seleção
switch ($choice) {
    "1" { 
        $terraformAction = "apply"
        $color = "Green"
    }
    "2" { 
        $terraformAction = "destroy"
        $color = "Red"
    }
    "Q" { 
        Write-Host "Operação cancelada pelo usuário." -ForegroundColor Yellow
        exit 
    }
    Default { 
        Write-Host "Opção inválida." -ForegroundColor Red
        exit 
    }
}

# Confirmação de segurança para Destroy
if ($terraformAction -eq "destroy") {
    $confirm = Read-Host "`n[CUIDADO] Você tem certeza que deseja DESTRUIR a infra? (S/N)"
    if ($confirm -ne "S") { Write-Host "Abortando..."; exit }
}

Write-Host "`nIniciando 'terraform $terraformAction'..." -ForegroundColor $color

# --- EXECUÇÃO E MÉTRICAS ---

$startTime = Get-Date
$argumentos = @($terraformAction, "-auto-approve")

try {
    # Start-Process permite ver a saída em tempo real no console (streaming)
    $process = Start-Process terraform -ArgumentList $argumentos -NoNewWindow -Wait -PassThru
}
finally {
    $endTime = Get-Date
    $duration = $endTime - $startTime

    Write-Host "`n===============================================" -ForegroundColor Cyan
    Write-Host "   RESUMO DA OPERAÇÃO TERRAFORM"               -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    
    Write-Host "Ação Executada : " -NoNewline; Write-Host $terraformAction.ToUpper() -ForegroundColor $color
    Write-Host "Hora de Início : $($startTime.ToString('HH:mm:ss'))"
    Write-Host "Hora de Fim    : $($endTime.ToString('HH:mm:ss'))"
    Write-Host "Duração Total  : $($duration.Minutes) min $($duration.Seconds) seg"

    if ($process.ExitCode -eq 0) {
        Write-Host "Status Final   : SUCESSO" -ForegroundColor Green
    } else {
        Write-Host "Status Final   : FALHA (Erro: $($process.ExitCode))" -ForegroundColor Red
    }
    Write-Host "===============================================`n" -ForegroundColor Cyan
}