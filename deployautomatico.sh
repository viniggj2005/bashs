#!/bin/bash
# Ler o nome do projeto
read -p "Digite o nome do Repositório: " repository

# Verificar se a porta já está em uso
port=$(docker port "$repository" 2>/dev/null | cut -d ':' -f 2)
if [ -n "$port" ]; then
    echo -e "A porta encontrada é: \e[31m$port\e[0m"
else
    while true; do #requisitar uma porta ao usuário até ele fornecer uma porta que não está em uso
        read -p "Digite a porta do projeto: " port
        verifyport=$(docker ps --format '{{.Ports}}' | grep -w "$port")
        if [ -n "$verifyport" ]; then
            echo -e "A porta: \e[31m$port já está em uso\e[0m"
        else
            break
        fi
    done
fi

# Verificar se o diretório do projeto existe e realizar o git pull ou clone
if [ -d "/documentos/github/$repository" ]; then
    cd /documentos/github/$repository/
    git checkout main
    git pull origin main
else #Caso não exista clonar o repositório diretamente do github.
    cd /documentos/github
    git clone -b main git@github.com:NOMEDEUSUÁRIOGITHUB/$repository.git
    cd /documentos/github/$repository/
fi

# Verificar se o projeto necessita de volume
while true; do #requsitar uma resposta até o usuário fornecer uma resposta esperada.
    read -p "O projeto necessita de um volume? [y/n] " volume
    if [ "$volume" = "y" ] || [ "$volume" = "n" ]; then
        break
    else
        echo -e "Entrada inválida. Por favor, digite \e[32m'y'\e[0m para sim ou \e[31m'n'\e[0m para não."
    fi
done

# Se o volume for necessário, verificar se o diretório existe ou criar o mesmo.
if [ "$volume" = "y" ]; then
    if [ -d "/mnt/$repository" ]; then
        echo "Volume já existe"
    else
        mkdir /mnt/$repository
        echo -e "\e[32mO volume foi criado!!!\e[0m"
    fi
    workdir=$(grep -i 'ENV DATA_DIR' Dockerfile | awk -F'=' '{print $2}' 2>/dev/null | xargs)
    echo -e "workdir: \e[32m$workdir\e[0m"
    if [ -z "$workdir" ]; then
    read -p "Qual diretório do projeto deverá ser referenciado no volume? " workdir
    fi
else
    echo "Sem Volume"
fi

# Verificar e copiar o arquivo .env, se existente
if [ -f "/documentos/envs/$repository.txt" ]; then
    cp -i /documentos/envs/$repository.txt /documentos/github/$repository/.env
    echo -e "\e[32m.env encontrado!!!\e[0m"
else #caso contrário encerra o processo mandando o usuário criar a env
    echo -e "\e[31m.env não encontrado na pasta envs, crie o mesmo!!!\e[0m"
    exit 1
fi

# Obter a versão do package.json e a porta exposta do Dockerfile
version=$(cat package.json 2>/dev/null \
    | grep version \
    | head -1 \
    | awk -F: '{ print $2 }' \
    | sed 's/[",]//g')

expose=$(grep -i '^EXPOSE' Dockerfile | awk '{print $2}' 2>/dev/null)

#Verificar se a porta foi encontrada no Dockerfile
if [ -z "$expose" ]; then #caso não tenha porta exposta no Dockerfile ele encerra o processo e manda o usuário ajustar o Dockerfile
    echo -e "\e[31mNão tem uma porta exposta, ajuste o Dockerfile\e[0m"
    exit 1
else #caso tenha porta exposta no Dockerfile ele printa ela para usuário ver.
    echo -e "Sua porta exposta é:\e[33m$expose\e[0m"
fi

# Se não houver versão no package.json, ele solicitará ela ao usuário.
if [ -z "$version" ]; then
    while true; do
        read -p "Insira a versão da imagem que será montada: " version
        if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
            echo -e "\e[32mO valor '$version' está no formato correto.\e[0m"
            break
        else
            echo -e "\e[31mFormato inválido.\e[0m Por favor, insira no formato \e[34m0.0\e[0m ou \e[34m.0.0.0\e[0m"
        fi
    done
else
    echo -e "Versão:\e[36m $version\e[0m"
    version=${version//[[:blank:]]/}
fi

# Build da repositorym Docker
docker build -t $repository:$version .
docker tag $repository:$version $repository:latest | 2>/dev/null #Renomeia a imagem que montou para latest

# Parar e remover o container existente
docker stop $repository 2>/dev/null #O 2>/dev/null serve para que caso não haja container ele não retorne o erro de container não econtrado para o usuário 
docker rm $repository 2>/dev/null #O 2>/dev/null serve para que caso não haja container ele não retorne o erro de container não econtrado para o usuário 

# Executar o container com ou sem volume
if [ "$volume" = "y" ]; then #Caso tenha sido requisitado um volume será usado este comando para subir o container com o seu volume.
    #echo " docker run -it -d -v /mnt/$repository:$workdir -p $port:$expose --name $repository $repository"
    docker run -it -d -v /mnt/$repository:$workdir -p $port:$expose --name $repository $repository | 2>/dev/null
else #Caso contrario ele subirá o container com este comando.
    docker run -it -d -p $port:$expose --name $repository $repository |2>/dev/null
fi
