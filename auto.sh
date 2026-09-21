#!/bin/bash

# Cores
AMARELO="\e[33m"
VERMELHO="\e[31m"
VERDE="\e[32m"
VERDE_LIMAO="\e[92m"
AZUL_CLARO="\e[96m"
ROXO_CLARO="\e[95m"
LARANJA="\e[93m" 
BRANCO="\e[97m"
NC="\033[0m"

# Verifica o status (sucesso/falha)
status() {
  if [ $? -eq 0 ]; then
    echo -e "${VERDE}✅ Concluído${NC}\n"
  else
    echo -e "${VERMELHO}❌ Falhou${NC}\n"
  fi
}

# Verifica se é root
if [[ "$EUID" -ne 0 ]]; then
  echo -e "${VERMELHO}❌ Execute root!"
  exit 1
fi

# Verifica distribuição e versão do Ubuntu
OS_NAME=$(grep '^NAME=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
OS_VERSION=$(grep '^VERSION_ID=' /etc/os-release | cut -d '=' -f2 | tr -d '"')
OS_MAIOR=$(echo "$OS_VERSION" | cut -d '.' -f1)
OS_MENOR=$(echo "$OS_VERSION" | cut -d '.' -f2)
VERSION_NUM=$(echo "$OS_MAIOR.$OS_MENOR" | bc 2>/dev/null)

if [[ "$OS_NAME" != "Ubuntu" ]]; then
    echo -e "\n${VERMELHO}❌ Versão do script não é suportada com a Distribuição: ${ROXO_CLARO}${OS_NAME} ${OS_VERSION}${NC}"
	echo -e "\n${BRANCO}✅ Versão do script suportada apenas para Distribuições: ${AMARELO}Debian ${BRANCO}| ${AMARELO}Ubuntu${NC}\n"

    exit 1
fi

if (( $(echo "$VERSION_NUM <= 20.04" | bc -l) )); then
    echo -e "\n${VERMELHO}❌ Versão do Ubuntu não suportada oficialmente pelo Zabbix 7.2. Use ${AMARELO}22.04 ${VERMELHO}ou ${AMARELO}superior ${VERMELHO}(ex: ${AMARELO}22.04 ${VERMELHO}, ${AMARELO}24.04${VERMELHO})${NC}\n"
    exit 1
fi

clear

# Banner ASCII
echo -e "${VERMELHO}"
cat << "EOF"
		 █████╗ ██╗   ██╗████████╗ ██████╗
		██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗
		███████║██║   ██║   ██║   ██║   ██║
		██╔══██║██║   ██║   ██║   ██║   ██║
		██║  ██║╚██████╔╝   ██║   ╚██████╔╝
		╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝ 
EOF
echo
echo

echo -e "${BRANCO}:: Iniciando instalação do ${LARANJA}MySQL ${BRANCO}+ ${LARANJA}Zabbix ${BRANCO}+ ${LARANJA}Grafana ${BRANCO}::"
echo -e "${BRANCO}:: ${AZUL_CLARO}Aguarde${BRANCO}..."
echo
echo

# Detecta SO e versão
echo -e "${BRANCO}💻 Detectando sistema operacional: ${ROXO_CLARO}${OS_NAME} ${OS_VERSION}"
echo
echo

# Baixa repositório Zabbix
echo -e "${BRANCO}📥 Baixando repositório do Zabbix para versão do Ubuntu ${ROXO_CLARO}${OS_VERSION}${BRANCO}:"
wget -q https://repo.zabbix.com/zabbix/7.4/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_7.4+ubuntu26.04_all.deb
status

# Instala o pacote .deb do repositório e atualiza
echo -e "${BRANCO}⏳ Atualizando repositório do Zabbix:"
dpkg -i zabbix-release_latest_7.4+ubuntu26.04_all.deb &>/dev/null
apt update -qq &>/dev/null
status

# Instala componentes do Zabbix
echo -e "${BRANCO}📦 Instalando pacotes Zabbix:"
apt install -y zabbix-server-mysql zabbix-frontend-php zabbix-apache-conf zabbix-sql-scripts zabbix-agent2 &>/dev/null
status

# Instala MySQL Server
echo -e "${BRANCO}📦 Instalando MySQL Server:"
apt install -y mysql-server &>/dev/null
status

# Solicita senha root do MySQL
read -sp "$(echo -e "${BRANCO}🔑 Digite uma senha para o usuário ${ROXO_CLARO}ROOT ${BRANCO}do MySQL: ")" MYSQL_ROOT_PASS
echo
echo -e "${VERDE}✅ Senha digitada: ${AZUL_CLARO}${MYSQL_ROOT_PASS}"
echo

# Solicita senha do usuário Zabbix
read -sp "$(echo -e "${BRANCO}🔑 Digite uma senha para o usuário do banco Zabbix: ")" DB_PASS
echo
echo -e "${VERDE}✅ Senha digitada: ${AZUL_CLARO}${DB_PASS}"
echo

# Cria base de dados e altera autenticação do root
echo -e "${BRANCO}📦 Criando banco de dados Zabbix:"
mysql -u root <<EOF &>/dev/null
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
CREATE DATABASE IF NOT EXISTS zabbix CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
EOF
status

# Cria usuário zabbix e dá privilégios
echo -e "${BRANCO}⏳ Configurando usuário Zabbix:"
mysql -u root -p"${MYSQL_ROOT_PASS}" <<EOF &>/dev/null
CREATE USER IF NOT EXISTS 'zabbix'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON zabbix.* TO 'zabbix'@'localhost';
SET GLOBAL log_bin_trust_function_creators = 1;
EOF
status

# Importa schema inicial do Zabbix
echo -e "${BRANCO}🔄 Importando banco de dados do Zabbix:"
zcat /usr/share/zabbix/sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -u zabbix -p"${DB_PASS}" zabbix &>/dev/null
status

# Restaura config de binlogs e define idioma no banco
mysql -u root -p"${MYSQL_ROOT_PASS}" -e "SET GLOBAL log_bin_trust_function_creators = 0; USE zabbix; UPDATE users SET lang = 'pt_BR' WHERE lang != 'pt_BR';" &>/dev/null

# Ajusta password no config do Zabbix Server
echo -e "${BRANCO}⏳ Configurando arquivo ${ROXO_CLARO}ZABBIX.CONF${BRANCO}:"
sed -i "s/# DBPassword=/DBPassword=${DB_PASS}/" /etc/zabbix/zabbix_server.conf &>/dev/null
status

# Gera locale pt-br
echo -e "${BRANCO}⏳ Configurando idioma ${ROXO_CLARO}PT-BR${BRANCO}:"
locale-gen pt_BR.UTF-8 &>/dev/null
status

# Cria arquivo de configuração do frontend para pular setup
echo -e "${BRANCO}⏳ Configurando frontend do Zabbix:"
cat <<EOF > /etc/zabbix/web/zabbix.conf.php
<?php
\$DB['TYPE']     = 'MYSQL';
\$DB['SERVER']   = 'localhost';
\$DB['PORT']     = '0';
\$DB['DATABASE'] = 'zabbix';
\$DB['USER']     = 'zabbix';
\$DB['PASSWORD'] = '${DB_PASS}';

\$DB['SCHEMA'] = '';
\$DB['ENCRYPTION'] = false;
\$DB['KEY_FILE'] = '';
\$DB['CERT_FILE'] = '';
\$DB['CA_FILE'] = '';
\$DB['VERIFY_HOST'] = false;
\$DB['CIPHER_LIST'] = '';
\$DB['FLOAT64'] = true;

\$ZBX_SERVER      = 'localhost';
\$ZBX_SERVER_PORT = '10051';
\$ZBX_SERVER_NAME = 'Zabbix Server';

\$IMAGE_FORMAT_DEFAULT = IMAGE_FORMAT_PNG;
EOF
status

# Instala Grafana
echo -e "${BRANCO}📦 Instalando Grafana:"
apt install -y apt-transport-https software-properties-common wget &>/dev/null
mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | tee /etc/apt/keyrings/grafana.gpg &>/dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" > /etc/apt/sources.list.d/grafana.list
apt update -qq &>/dev/null
apt install -y grafana &>/dev/null
status

# Reinicia e habilita serviços
echo -e "${BRANCO}🔁 Ativando e iniciando serviços:"
systemctl restart zabbix-server zabbix-agent2 apache2 grafana-server &>/dev/null
systemctl enable zabbix-server zabbix-agent2 apache2 grafana-server &>/dev/null
status

# Mensagem final
echo -e "${VERDE}🎉 Instalação finalizada com sucesso!"
echo
echo

# URLs de acessos
IP=$(hostname -I | awk '{print $1}')
echo -e "${AMARELO}🔗 Zabbix: ${BRANCO}http://${AZUL_CLARO}${IP}${BRANCO}/zabbix${BRANCO} (${AMARELO}login: ${AZUL_CLARO}Admin / zabbix${BRANCO})"
echo -e "${AMARELO}🔗 Grafana: ${BRANCO}http://${AZUL_CLARO}${IP}${BRANCO}:3000${BRANCO} (${AMARELO}login: ${AZUL_CLARO}admin / admin${BRANCO})"
echo
echo -e "${BRANCO}Script desenvolvido por: ${VERDE_LIMAO}BUG IT${NC}"
echo
