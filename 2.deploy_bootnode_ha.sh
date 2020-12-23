#! /bin/sh
##
## 此脚本用于自动化搭建高可用hyperledger besu的引导节点
##
## 注意事项：
## 1. 此脚本默认当前系统已经安装了docker服务并下载了最新的besu镜像
## 2. 脚本默认当前服务器已安装jq工具，若未安装可以通过yum -y install jq进行安装
## 3. 请使用本脚本前确定好引导节点的个数并在配置文件中做好定义
## 4. 配置文件只做修改不做新增或删除
## 5. 若存在异地组网情况，请先通过docker swarm创建overlay网络，并注意网络名称必须为besunetwork
##
## 配置内容（样例）：
## custom_folder=A_BOOT_NODE                                      # 引导节点名称
## deploy_path=/home/yzh/Documents/docker/besu/Clique             # clique节点安装路径
## clique_config_file=node_conf/clique_config.toml                # clique共识算法节点配置文件路径
## genesis_config_file=genesis_conf/clique_genesis.json           # 创世块文件路径
## ip_arr=192.18.0.2 192.18.0.3 192.18.0.4                        # 节点名称(自定义ip地址使用空格将两个ip分隔)
## docker_image=hyperledger/besu:20.10.0-RC2-openjdk-latest       # docker镜像名称
##
## @Date：2020-10-19
## @Author：yuanzhenhui
##

# 获取部署节点路径
deploy_path=$(sed '/^deploy_path=/!d;s/.*=//' generate_conf/bootnode.cnf)

# 获取用户定义的节点文件夹名称
custom_folder=$(sed '/^custom_folder=/!d;s/.*=//' generate_conf/bootnode.cnf)

# 获取配置文件
clique_config_file=$(sed '/^clique_config_file=/!d;s/.*=//' generate_conf/bootnode.cnf)

# 获取创世块文件
genesis_config_file=$(sed '/^genesis_config_file=/!d;s/.*=//' generate_conf/bootnode.cnf)

# 获取docker容器固定ip地址
ip_arr=$(sed '/^ip_arr=/!d;s/.*=//' generate_conf/bootnode.cnf)

# docker镜像名称
docker_image=$(sed '/^docker_image=/!d;s/.*=//' generate_conf/bootnode.cnf)

# 1. 将配置文件中的多个ip转换成ip数组
ip_arrs=($ip_arr)

# 2. 先判断目录节点是否存在如果不存在就建立部署目录
if [ ! -d $deploy_path ]; then
  sudo mkdir -p $deploy_path

  # 3. 定义http端口的初始值
  declare -i hp=8745

  # 4. 定义p2p端口的初始值
  declare -i p2p=31003

  # 5. 遍历ip数组
  for i in "${!ip_arrs[@]}"; do

    # 6. 生成部署目录路径
    target_folder=$deploy_path"/"$custom_folder"_HA_"$i

    # 7. 判断部署是否存在
    if [ ! -d $target_folder ]; then

      # 8. 部署目录不存在则创建部署目录
      sudo mkdir -p $target_folder

      # 9. 拷贝创世块和引导节点配置文件文件到部署目录
      sudo cp $genesis_config_file $target_folder && sudo cp $clique_config_file $target_folder

      # 10. 在部署目录里面创建一个data的目录
      data_folder=$target_folder"/data"
      sudo mkdir -p $data_folder && sudo chmod 777 $data_folder

      # 11. 通过`sudo docker run`启动引导节点，返回的容器id将传入container_id变量
      container_id=$(sudo docker run --name bootnode$i --network=besunetwork --ip ${ip_arrs[i]} -p $p2p:30303 -p $hp:8545 -v $target_folder:/var/lib/besu -d $docker_image --config-file=/var/lib/besu/clique_config.toml)

      # 12. 由于docker启动时异步执行的，为了保证有足够的时间启动docker并获取到容器id，所以这里休眠的2秒
      sleep 2s

      # 13. 接着通过`docker exec`执行导出节点签名地址到文档，这个生成过程给到8秒的休眠
      sudo docker exec -itd $container_id /bin/sh -c "besu --data-path=/var/lib/besu/data public-key export-address --to=/var/lib/besu/data/bootnode"$i"_address"
      sleep 8s

      # 14. 之后通过容器id关闭当前容器
      sudo docker stop $container_id

      # 15. 最终将http端口、容器id和ip地址分别以”-“进行连接并寄存到名为`container_arr`变量中
      container_arr="$container_arr $hp-$container_id-${ip_arrs[i]}"

      # 16. 将部署目录路径用字符串变量存起来
      target_root="$target_root $i-$target_folder"

      # 17. 同理，将签名地址文件路径也放入到address_file变量中，通过读取address_file输出将其放入`signer_address`变量中进行拼接。
      address_file=$data_folder"/bootnode"$i"_address"
      for line in $(cat $address_file); do
        signer_address=$signer_address${line##*0x}
      done

      # 18. 在循环的末尾对http端口和p2p端口进行累加处理生成新的端口号。
      let hp=hp+10
      let p2p=p2p+10
    fi
  done

  # 19. 对部署路径数组进行遍历
  for z in ${target_root[@]}; do

    # 20. 通过遍历出来的数据通过切割字符串的方式获取到下标和路径
    zidx=$(echo $z | cut -d \- -f 1)
    path=$(echo $z | cut -d \- -f 2)

    # 21. 路径结合”`/clique_genesis.json`“将生成clique_genesis.json模板读取路径
    target_genesis=$path"/clique_genesis.json"

    # 22. 由于之前已经将clique_genesis.json模板拷贝到部署目录了，所以这里需要将`clique_genesis.json`修改权限并使用sed命令对clique_genesis.json中”`<Node 1 Address>`“字眼进行替换，最终替换成signer_address变量内容
    sudo chmod 777 $target_genesis && sudo sed -i "s/<Node 1 Address>/$signer_address/g" $target_genesis

    # 23. 如果这次循环时第一次循环，则还需要将修改好的clique_genesis.json拷贝回配置目录中并根据自定义目录名称重新命名clique_genesis.json文件
    if [ $zidx -eq 0 ]; then
      sudo cp $target_genesis genesis_conf/$(echo $custom_folder | tr '[A-Z]' '[a-z]')"_clique_genesis.json"
    fi

    # 24. 同理，使用路径结合”`/clique_config.toml`“得到拷贝到部署目录中的clique_config.toml文件路径
    target_config=$path"/clique_config.toml"

    # 25. 修改clique_config.toml的执行权限并且在文件的末尾追加创世块的文件路径
    sudo chmod 777 $target_config && echo -e "\n\n # Chain \n genesis-file=\"/var/lib/besu/clique_genesis.json\"  # 创世块文件地址路径" >>$target_config

    # 26. 完成以上两个配置文件的修改后，删除部署目录中data文件夹下除签署地址和key之外的所有文件
    sudo cp $path"/data/"*"_address" $path && sudo cp $path"/data/key" $path
    sudo rm -rf $path"/data/"*
    sudo mv $path"/"*"_address" $path"/data" && sudo mv $path"/key" $path"/data"
    sudo chmod 777 -R $path"/data"
  done

  # 27. 遍历容器数组将遍历结果通过字符串分割获取到http端口，容器id和ip地址
  for v in ${container_arr[@]}; do
    sleep 2s
    hps=$(echo $v | cut -d \- -f 1)
    cai=$(echo $v | cut -d \- -f 2)
    ips=$(echo $v | cut -d \- -f 3)

    # 28. 通过容器id启动docker容器
    sudo docker start $cai

    # 29. docker启动后休眠8秒等待容器启动完成
    sleep 8s

    # 30. 使用curl命令调用besu的`JSON RPC API`访问的是本节点的method接口
    enode_json=$(curl -X POST --data '{"jsonrpc":"2.0","method":"net_enode","params":[],"id":1}' http://127.0.0.1:$hps)

    # 31. 在休眠2秒后将会得到enode_json的返回，之后通过jq解析返回json得到enode的地址
    sleep 2s
    enode_val=$(echo $enode_json | jq '.result')

    # 32. 使用替换的方式将enode地址中的`127.0.0.1替换成对外的固定ip地址`
    bnenode_arr=$bnenode_arr${enode_val/127.0.0.1/$ips}","

    # 33. 然后再次通过容器id停止容器
    sudo docker stop $cai
  done

  # 34. 再次使用部署目录循环，获取到部署目录地址
  for z in ${target_root[@]}; do
    path=$(echo $z | cut -d \- -f 2)

    # 35. 根据拼接字符串重新获取到clique_config.toml文件的地址
    target_config=$path"/clique_config.toml"

    # 36. 在clique_config.toml文件中追加bootnodes配置参数，将之前整理的关于各引导节点的enode写到里面
    sudo chmod 777 $target_config && echo -e "\n # Network \n bootnodes=[${bnenode_arr%?}]  # 引导节点配置" >>$target_config
  done

  # 37. 将写好的clique_config文件根据自定义名称重新命名并拷贝到配置目录中
  vn_toml=$(sudo echo $custom_folder | tr '[A-Z]' '[a-z]')"_clique_config"
  vn_path=node_conf/$vn_toml".toml"
  sudo cp node_conf/clique_config.toml $vn_path && sudo chmod 777 $vn_path

  # 38. 将配置目录中的创世块文件名称和和引导节点enode地址都写入到自定义命名的clique_config文件中
  echo -e "\n\n # Chain \n genesis-file=\"/var/lib/besu/$(echo $custom_folder | tr '[A-Z]' '[a-z]')_clique_genesis.json\"   # 创世块文件地址路径" >>$vn_path
  echo -e "\n # Network \n bootnodes=[${bnenode_arr%?}]   # 引导节点配置" >>$vn_path

  for v in ${container_arr[@]}; do
    cai=$(echo $v | cut -d \- -f 2)

    # 39. 重新根据容器id启动docker容器
    sudo docker start $cai
  done
fi
