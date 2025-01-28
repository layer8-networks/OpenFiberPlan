
#!/bin/bash

# Atualizar sistema e instalar dependências
echo "Atualizando o sistema..."
sudo apt update && sudo apt upgrade -y
echo "Instalando dependências..."
sudo apt install -y python3 python3-pip python3-venv postgresql postgresql-contrib nginx git curl

# Configurar banco de dados PostgreSQL
echo "Configurando banco de dados PostgreSQL..."
sudo -u postgres psql -c "CREATE DATABASE openfiberplan;"
sudo -u postgres psql -c "CREATE USER openfiberuser WITH PASSWORD 'senha_segura';"
sudo -u postgres psql -c "ALTER ROLE openfiberuser SET client_encoding TO 'utf8';"
sudo -u postgres psql -c "ALTER ROLE openfiberuser SET default_transaction_isolation TO 'read committed';"
sudo -u postgres psql -c "ALTER ROLE openfiberuser SET timezone TO 'UTC';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE openfiberplan TO openfiberuser;"

# Criar ambiente virtual e instalar dependências do backend
echo "Configurando o backend Django..."
cd ~
python3 -m venv openfiber_env
source openfiber_env/bin/activate
pip install --upgrade pip
pip install django djangorestframework psycopg2-binary django-cors-headers networkx djoser

# Configurar o backend Django
git clone https://github.com/layer8-networks/OpenFiberPlan.git
cd openfiberplan
sed -i "s/sua_senha/senha_segura/g" openfiberplan/settings.py
python manage.py makemigrations
python manage.py migrate
python manage.py createsuperuser --username admin --email admin@example.com
python manage.py collectstatic --no-input

# Configurar o serviço Gunicorn
echo "Configurando o Gunicorn..."
cat <<EOT | sudo tee /etc/systemd/system/openfiberplan.service
[Unit]
Description=Gunicorn server para OpenFiberPlan
After=network.target

[Service]
User=$USER
Group=www-data
WorkingDirectory=/home/$USER/openfiberplan
ExecStart=/home/$USER/openfiber_env/bin/gunicorn --workers 3 --bind unix:/home/$USER/openfiberplan/openfiberplan.sock openfiberplan.wsgi:application

[Install]
WantedBy=multi-user.target
EOT

sudo systemctl start openfiberplan
sudo systemctl enable openfiberplan

# Configurar o Nginx
echo "Configurando o Nginx..."
sudo rm /etc/nginx/sites-enabled/default
cat <<EOT | sudo tee /etc/nginx/sites-available/openfiberplan
server {
    listen 80;
    server_name localhost;

    location / {
        proxy_pass http://unix:/home/$USER/openfiberplan/openfiberplan.sock;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }

    location /static/ {
        root /home/$USER/openfiberplan;
    }
}
EOT

sudo ln -s /etc/nginx/sites-available/openfiberplan /etc/nginx/sites-enabled
sudo nginx -t
sudo systemctl restart nginx

# Instalar o frontend React.js
echo "Configurando o frontend React.js..."
cd ~
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs
cd openfiberplan/frontend
npm install
npm run build
sudo cp -r build/* /var/www/html/

echo "Instalação concluída! O sistema OpenFiberPlan está disponível no endereço http://<IP_DO_SERVIDOR>."
