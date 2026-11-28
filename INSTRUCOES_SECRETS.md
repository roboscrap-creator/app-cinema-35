# Segredos necessarios no GitHub Actions (Settings -> Secrets and variables -> Actions)

O build em `.github/workflows/build_apk.yml` nao usa mais senha fixa no texto.
Todos os valores sensiveis vem de **Repository secrets**. Adicione cada um em:
`github.com/roboscrap-creator/app-cinema-35` -> Settings -> Secrets and
variables -> Actions -> New repository secret.

## 1. Assinatura do APK (obrigatoria para release)

| Nome do secret | Como gerar/valor |
|---|---|
| `KEYSTORE_JKS_B64` | Conteudo de `cinema-release.jks` em base64. No Termux, na pasta do projeto: `base64 -w0 cinema-release.jks` e cole a saida. |
| `KEYSTORE_STORE_PASSWORD` | Senha do keystore. Atual: `cinema35pass` (recomendado trocar na proxima geracao). |
| `KEYSTORE_KEY_PASSWORD` | Senha da chave. Atual: `cinema35pass`. |
| `KEYSTORE_KEY_ALIAS` | Alias da chave: `cinema`. |

> O `.jks` fica fora do controle de versao (`.gitignore` ignora `*.jks`).
> Guarde uma copia local; sem ele nao e possivel assar atualizacoes compativeis.

## 2. Dados e servicos

| Nome do secret | Finalidade |
|---|---|
| `TMDB_API_KEY` | Metadados, elenco/diretor e rankings Top100. Chave gratuita em themoviedb.org -> Settings -> API. |
| `CINEMAX_APP_SECRET` | Cabecalho `X-App-Secret` do backend em Render. |
| `GEMINI_API_KEY` | Usado pelo backend/Edge Function; repassado no build. |
| `GEMINI_API_KEY_2` | Segunda chave de fallback do backend. |

## 3. Auditoria de catalogo (opcionais)

| Nome do secret | Finalidade |
|---|---|
| `SCRAPE_WEBHOOK_URL` | Webhook dos problemas detectados pelo `catalog_audit_service.dart`. |
| `GITHUB_PEDIDOS_TOKEN` | Token com `issues: write` para abrir issues de links sem peers, duracao trocada e series incompletas. |

## Fluxo apos configurar

1. `flutter pub get` (onde houver Flutter) apos remover dependencias.
2. Suba as alteracoes para `main`; o workflow usa os secrets automaticamente.
3. Na primeira build sem `KEYSTORE_JKS_B64` o workflow falha com mensagem clara
   dizendo qual secret falta; e esperado ate o secret ser adicionado.
4. Validacao local (se Flutter instalado): `flutter analyze` e
   `flutter test test/visual_audit_test.dart`.
