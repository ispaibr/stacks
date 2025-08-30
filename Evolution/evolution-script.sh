#!/bin/bash

# =============================================================================
# CONFIGURAÇÃO DE HOSTS E IPS - PERSONALIZE AQUI ANTES DE EXECUTAR
# =============================================================================

# Hosts e IPs dos serviços (PERSONALIZE CONFORME SUA INFRAESTRUTURA)
REDIS_HOST="redis-db"
REDIS_PORT="6379"
REDIS_DB="3"

POSTGRES_HOST="pgvector-main"
POSTGRES_PORT="5432"
POSTGRES_DB="evolution"
POSTGRES_USER="evolution"
POSTGRES_PASS="nuva_okia_2025"

CHATWOOT_POSTGRES_DB="chatwoot"
CHATWOOT_POSTGRES_USER="chatwoot"
CHATWOOT_POSTGRES_PASS="nuva_okia_2025"

RABBITMQ_HOST="rabbitmq"
RABBITMQ_PORT="5672"
RABBITMQ_USER="admin"
RABBITMQ_PASS="nuva_okia_2025"

MINIO_HOST="minio"
MINIO_PORT="9000"
MINIO_ROOT_USER="admin"
MINIO_ROOT_PASSWORD="nuva_okia_2025"

# IP do container Evolution API
EVOLUTION_IMAGE="latest"
EVOLUTION_REPOSITORY="evoapicloud/evolution-api"
EVOLUTION_HOST="10.249.255.30"

# Network Docker
DOCKER_NETWORK="network_public"

# Configurações S3/MinIO
S3_BUCKET="evolution"
S3_REGION="us-east-1"

# Configurações de Sessão WhatsApp (PERSONALIZE CONFORME NECESSÁRIO)
SESSION_PHONE_CLIENT="Windows 11"
SESSION_PHONE_NAME="Chrome"
SESSION_PHONE_VERSION="2.2413.51"

# Sentry Logs
SENTRY_DSN=""

# Open AI
OPENAI_API_KEY_GLOBAL=""

# Integrações (HABILITE/DESABILITE CONFORME NECESSÁRIO)
S3_ENABLED="true"
RABBITMQ_ENABLED="true"
RABBITMQ_GLOBAL_ENABLED="true"
TYPEBOT_ENABLED="false"
OPENAI_ENABLED="false"
DIFY_ENABLED="false"
SENTRY_ENABLED="false"


# =============================================================================
# SCRIPT EVOLUTION API - NÃO ALTERE ABAIXO DESTA LINHA
# =============================================================================

# Primeiro vamos verificar se o Redis está funcionando
echo "=== Verificando Redis ===";
docker ps | grep $REDIS_HOST;
echo "=== Testando conexão Redis ===";
docker exec $REDIS_HOST redis-cli ping || echo "Redis não está respondendo!";

# Verificar se RabbitMQ está funcionando
echo "=== Verificando RabbitMQ ===";
docker ps | grep $RABBITMQ_HOST || echo "RabbitMQ não está executando!";

# Verificar se MinIO está funcionando  
echo "=== Verificando MinIO ===";
docker ps | grep $MINIO_HOST || echo "MinIO não está executando!";

# Variáveis
NAME=evolution-api;
DOMAIN="$(hostname -f)";
FQDN="$NAME.$DOMAIN";
LOCAL=$NAME.intranet.br;
DATADIR=/storage/evolution-api;
# Obter timezone do HOST para usar no container
TZ="$(timedatectl show | egrep Timezone= | cut -f2 -d=)";
# Versão Evolution API - imagem oficial do repositório GitHub
EVOLUTION_VERSION=$EVOLUTION_IMAGE;
IMAGE=$EVOLUTION_REPOSITORY:$EVOLUTION_VERSION;
# Gerar API Key única para esta instalação
EVOLUTION_API_KEY="$(openssl rand -hex 32)";

# Configurações MinIO (S3) - Chaves geradas automaticamente
MINIO_ENDPOINT="http://$MINIO_HOST:$MINIO_PORT";
# Gerar chaves S3 únicas para esta instalação
S3_ACCESS_KEY="evolution_$(openssl rand -hex 8)";
S3_SECRET_KEY="$(openssl rand -hex 32)";

# Configurações RabbitMQ usando variáveis
RABBITMQ_URI="amqp://$RABBITMQ_USER:$RABBITMQ_PASS@$RABBITMQ_HOST:$RABBITMQ_PORT/default";

# Atualizar/baixar imagem:
docker pull $IMAGE;

# Diretório de dados persistentes:
mkdir -p $DATADIR/instances;
mkdir -p $DATADIR/store;

# Parar container atual:
docker rm -f $NAME 2>/dev/null;

# Criar database evolution no PostgreSQL existente (antes de rodar o container)
docker exec $POSTGRES_HOST psql -U postgres -c "CREATE DATABASE $POSTGRES_DB;" 2>/dev/null || true;
docker exec $POSTGRES_HOST psql -U postgres -c "CREATE USER $POSTGRES_USER WITH PASSWORD '$POSTGRES_PASS';" 2>/dev/null || true;
docker exec $POSTGRES_HOST psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;" 2>/dev/null || true;
docker exec $POSTGRES_HOST psql -U postgres -c "ALTER DATABASE $POSTGRES_DB OWNER TO $POSTGRES_USER;" 2>/dev/null || true;

# Aguardar serviços ficarem prontos
echo "Aguardando Redis, PostgreSQL, RabbitMQ e MinIO...";
sleep 5;

# Configurar MinIO ANTES de rodar o container Evolution
echo "=== CONFIGURANDO MINIO S3 ===";
docker exec $MINIO_HOST mc alias set local http://localhost:$MINIO_PORT $MINIO_ROOT_USER $MINIO_ROOT_PASSWORD 2>/dev/null || echo "Alias já existe";
docker exec $MINIO_HOST mc mb local/$S3_BUCKET 2>/dev/null || echo "Bucket já existe";
docker exec $MINIO_HOST mc anonymous set download local/$S3_BUCKET 2>/dev/null || echo "Política já configurada";
# Criar chaves de acesso para Evolution API
docker exec $MINIO_HOST mc admin user add local $S3_ACCESS_KEY $S3_SECRET_KEY 2>/dev/null || echo "Usuário S3 já existe";
docker exec $MINIO_HOST mc admin policy attach local readwrite --user $S3_ACCESS_KEY 2>/dev/null || echo "Política já aplicada";
echo "MinIO configurado com chaves S3 geradas automaticamente";
echo;

# Rodar:
docker run \
  -d --restart=always \
  --name $NAME -h $LOCAL \
  --network $DOCKER_NETWORK \
  --ip=$EVOLUTION_HOST \
  --memory=2g --memory-swap=2g \
  \
  -e TZ=$TZ \
  -e SERVER_TYPE=http \
  -e SERVER_PORT=8080 \
  -e SERVER_URL="https://$FQDN" \
  \
  -e AUTHENTICATION_API_KEY="$EVOLUTION_API_KEY" \
  -e AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=false \
  \
  -e DATABASE_ENABLED=true \
  -e DATABASE_PROVIDER="postgresql" \
  -e DATABASE_CONNECTION_URI="postgresql://$POSTGRES_USER:$POSTGRES_PASS@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB" \
  -e DATABASE_CONNECTION_CLIENT_NAME="EvolutionAPI" \
  -e DATABASE_SAVE_DATA_INSTANCE=true \
  -e DATABASE_SAVE_DATA_NEW_MESSAGE=false \
  -e DATABASE_SAVE_MESSAGE_UPDATE=false \
  -e DATABASE_SAVE_DATA_CONTACTS=true \
  -e DATABASE_SAVE_DATA_CHATS=false \
  -e DATABASE_SAVE_DATA_LABELS=true \
  -e DATABASE_SAVE_DATA_HISTORIC=false \
  \
  -e CACHE_REDIS_ENABLED=true \
  -e CACHE_REDIS_URI="redis://$REDIS_HOST:$REDIS_PORT/$REDIS_DB" \
  -e CACHE_REDIS_PREFIX_KEY="evo" \
  -e CACHE_REDIS_SAVE_INSTANCES=false \
  -e CACHE_LOCAL_ENABLED=false \
  \
  -e LOG_LEVEL=ERROR \
  -e LOG_COLOR=true \
  -e LOG_BAILEYS=error \
  \
  -e DEL_INSTANCE=false \
  -e LANGUAGE=pt-BR \
  \
  -e CONFIG_SESSION_PHONE_CLIENT="$SESSION_PHONE_CLIENT" \
  -e CONFIG_SESSION_PHONE_NAME="$SESSION_PHONE_NAME" \
  -e CONFIG_SESSION_PHONE_VERSION="$SESSION_PHONE_VERSION" \
  \
  -e QRCODE_LIMIT=6 \
  -e QRCODE_COLOR="#198754" \
  \
  -e WA_BUSINESS_TOKEN_WEBHOOK="evolution" \
  -e WA_BUSINESS_URL="https://graph.facebook.com" \
  -e WA_BUSINESS_VERSION="v20.0" \
  -e WA_BUSINESS_LANGUAGE="pt_BR" \
  \
  -e WEBHOOK_GLOBAL_ENABLED=true \
  -e WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false \
  \
  -e WEBSOCKET_ENABLED=false \
  -e WEBSOCKET_GLOBAL_EVENTS=false \
  \
  -e S3_ENABLED=$S3_ENABLED \
  -e S3_ACCESS_KEY="$S3_ACCESS_KEY" \
  -e S3_SECRET_KEY="$S3_SECRET_KEY" \
  -e S3_ENDPOINT="$MINIO_HOST" \
  -e S3_BUCKET="$S3_BUCKET" \
  -e S3_PORT=$MINIO_PORT \
  -e S3_USE_SSL=false \
  -e S3_REGION="$S3_REGION" \
  -e S3_FORCE_PATH_STYLE=true \
  \
  -e RABBITMQ_ENABLED=$RABBITMQ_ENABLED \
  -e RABBITMQ_URI="$RABBITMQ_URI" \
  -e RABBITMQ_EXCHANGE_NAME="evolution_v2" \
  -e RABBITMQ_GLOBAL_ENABLED=$RABBITMQ_GLOBAL_ENABLED \
  \
  -e TYPEBOT_ENABLED=$TYPEBOT_ENABLED \
  -e TYPEBOT_API_VERSION="latest" \
  -e TYPEBOT_KEEP_OPEN=true \
  -e TYPEBOT_SEND_MEDIA_BASE64=true \
  \
  -e CHATWOOT_ENABLED=true \
  -e CHATWOOT_MESSAGE_READ=true \
  -e CHATWOOT_IMPORT_DATABASE_CONNECTION_URI="postgresql://$CHATWOOT_POSTGRES_USER:$CHATWOOT_POSTGRES_PASS@$POSTGRES_HOST:$POSTGRES_PORT/$CHATWOOT_POSTGRES_DB?sslmode=disable" \
  -e CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true \
  \
  -e OPENAI_ENABLED=$OPENAI_ENABLED \
  -e OPENAI_API_KEY_GLOBAL="$OPENAI_API_KEY_GLOBAL" \
  -e DIFY_ENABLED=$DIFY_ENABLED \
  \
  -e SENTRY_DSN="$SENTRY_DSN" \
  \
  -v $DATADIR/instances:/evolution/instances \
  -v $DATADIR/store:/evolution/store \
  \
  --label "traefik.enable=true" \
  --label "traefik.http.routers.$NAME.rule=Host(\`$FQDN\`)" \
  --label "traefik.http.routers.$NAME.entrypoints=websecure" \
  --label "traefik.http.routers.$NAME.tls=true" \
  --label "traefik.http.routers.$NAME.tls.certresolver=letsencrypt" \
  --label "traefik.http.services.$NAME.loadbalancer.server.port=8080" \
  --label "traefik.http.services.$NAME.loadbalancer.passHostHeader=true" \
  \
  $IMAGE;

# Aguardar container iniciar
sleep 10;

# Verificar se tudo está funcionando
echo;
echo "=== VERIFICAÇÃO DOS SERVIÇOS ===";
echo "Redis........: $(docker exec $REDIS_HOST redis-cli ping 2>/dev/null || echo 'ERRO')";
echo "PostgreSQL...: $(docker exec $POSTGRES_HOST psql -U postgres -c 'SELECT 1;' 2>/dev/null | grep -q '1' && echo 'OK' || echo 'ERRO')";
echo "RabbitMQ.....: $(docker exec $RABBITMQ_HOST rabbitmq-diagnostics -q ping 2>/dev/null && echo 'OK' || echo 'ERRO')";
echo "MinIO........: $(docker exec $MINIO_HOST mc --version >/dev/null 2>&1 && echo 'OK' || echo 'ERRO')";
echo "Evolution API: $(docker ps --format 'table {{.Names}}\t{{.Status}}' | grep evolution-api || echo 'ERRO')";
echo;

# Salvar configurações geradas
CONFIG_FILE="/storage/evolution-api/config_instalacao.txt";
mkdir -p "/storage/evolution-api";
cat > $CONFIG_FILE << EOF
=== EVOLUTION API - CONFIGURAÇÕES ===
Data: $(date '+%d/%m/%Y %H:%M:%S')

ACESSOS PRINCIPAIS:
Evolution API: https://$FQDN
Manager: https://$FQDN/manager
API Key: $EVOLUTION_API_KEY

CHAVES S3/MINIO (GERADAS AUTOMATICAMENTE):
Access Key: $S3_ACCESS_KEY
Secret Key: $S3_SECRET_KEY
Bucket: $S3_BUCKET
Endpoint: $MINIO_ENDPOINT

SERVIÇOS INTEGRADOS:
MinIO: https://$MINIO_HOST.$DOMAIN
RabbitMQ: https://$RABBITMQ_HOST.$DOMAIN
ChatWoot: https://chat.$DOMAIN

CONEXÕES INTERNAS:
Redis: redis://$REDIS_HOST:$REDIS_PORT/$REDIS_DB
PostgreSQL: postgresql://$POSTGRES_USER:$POSTGRES_PASS@$POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB
RabbitMQ: $RABBITMQ_URI

HOSTS CONFIGURADOS:
Redis Host: $REDIS_HOST:$REDIS_PORT
PostgreSQL Host: $POSTGRES_HOST:$POSTGRES_PORT
RabbitMQ Host: $RABBITMQ_HOST:$RABBITMQ_PORT
MinIO Host: $MINIO_HOST:$MINIO_PORT
Container IP: $EVOLUTION_HOST
Network: $DOCKER_NETWORK

CONFIGURAÇÕES DE SESSÃO:
Phone Client: $SESSION_PHONE_CLIENT
Phone Name: $SESSION_PHONE_NAME
Phone Version: $SESSION_PHONE_VERSION

INTEGRAÇÕES HABILITADAS:
Database: true
Cache Redis: true
Cache Local: false
S3/MinIO: $S3_ENABLED
RabbitMQ: $RABBITMQ_ENABLED
RabbitMQ Global: $RABBITMQ_GLOBAL_ENABLED
Webhook Global: true
WebSocket: false
Typebot: $TYPEBOT_ENABLED
ChatWoot: true
OpenAI: $OPENAI_ENABLED
Dify: $DIFY_ENABLED
Sentry: $SENTRY_ENABLED
EOF

# Acesso:
echo "=== 🚀 EVOLUTION API INSTALADA COM SUCESSO! ===";
echo;
echo "📍 ACESSOS PRINCIPAIS:";
echo "Evolution API: https://$FQDN";
echo "Manager......: https://$FQDN/manager";
echo "API Key......: $EVOLUTION_API_KEY";
echo;
echo "🔑 CHAVES S3 GERADAS:";
echo "Access Key: $S3_ACCESS_KEY";
echo "Secret Key: $S3_SECRET_KEY";
echo "Bucket....: $S3_BUCKET";
echo;
echo "🔗 SERVIÇOS INTEGRADOS:";
echo "MinIO....: https://$MINIO_HOST.$DOMAIN";
echo "RabbitMQ.: https://$RABBITMQ_HOST.$DOMAIN";
echo "ChatWoot.: https://chat.$DOMAIN";
echo;
echo "🖧 HOSTS CONFIGURADOS:";
echo "Redis....: $REDIS_HOST:$REDIS_PORT";
echo "PostgreSQL: $POSTGRES_HOST:$POSTGRES_PORT";
echo "RabbitMQ.: $RABBITMQ_HOST:$RABBITMQ_PORT";
echo "MinIO....: $MINIO_HOST:$MINIO_PORT";
echo "Container IP: $EVOLUTION_HOST";
echo;
echo "📱 SESSÃO WHATSAPP:";
echo "Client...: $SESSION_PHONE_CLIENT";
echo "Name.....: $SESSION_PHONE_NAME";
echo "Version..: $SESSION_PHONE_VERSION";
echo;
echo "🔗 INTEGRAÇÕES:";
echo "Database.....: true";
echo "Cache Redis..: true";
echo "Cache Local..: false";
echo "S3/MinIO.....: $S3_ENABLED";
echo "RabbitMQ.....: $RABBITMQ_ENABLED";
echo "RabbitMQ Glob: $RABBITMQ_GLOBAL_ENABLED";
echo "Webhook Glob.: true";
echo "WebSocket....: false";
echo "Typebot......: $TYPEBOT_ENABLED";
echo "ChatWoot.....: true";
echo "OpenAI.......: $OPENAI_ENABLED";
echo "Dify.........: $DIFY_ENABLED";
echo "Sentry.......: $SENTRY_ENABLED";
echo;
echo "💾 CONFIGURAÇÕES SALVAS EM: $CONFIG_FILE";
echo;

# Comandos úteis para diagnóstico
echo "🔧 COMANDOS ÚTEIS:";
echo "# Ver logs: docker logs -f evolution-api";
echo "# Status: docker ps | grep evolution-api";
echo "# Reiniciar: docker restart evolution-api";