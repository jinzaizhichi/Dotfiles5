#!/bin/bash
# Rime 输入法重建脚本
# 功能：删除 build 目录并重新编译所有配置
# 注意：会自动备份和恢复扩展词库文件（*.extended.*）

# 注意：不使用 set -e，因为 macOS 上可能没有某些命令

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本所在目录（scripts 目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Rime 配置目录（scripts 的父目录，或使用第一个参数）
RIME_DIR="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUILD_DIR="$RIME_DIR/build"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Rime 输入法重建脚本${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# 检查目录是否存在
if [ ! -d "$RIME_DIR" ]; then
    echo -e "${RED}错误：配置目录不存在: $RIME_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}配置目录: $RIME_DIR${NC}"
echo ""

# 检查 build 目录是否存在
BACKUP_DIR="/tmp/rime_build_backup_$$"
EXTENDED_FILES_RESTORED=false

if [ -d "$BUILD_DIR" ]; then
    # 计算 build 目录大小
    BUILD_SIZE=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
    echo -e "${YELLOW}检测到 build 目录，大小: $BUILD_SIZE${NC}"
    
    # 备份扩展词库文件（如果存在）
    EXTENDED_FILES=$(find "$BUILD_DIR" -name "*.extended.*" -type f 2>/dev/null)
    if [ -n "$EXTENDED_FILES" ]; then
        echo -e "${YELLOW}检测到扩展词库文件，正在备份...${NC}"
        mkdir -p "$BACKUP_DIR"
        BACKUP_COUNT=0
        while IFS= read -r file; do
            if [ -f "$file" ]; then
                RELATIVE_PATH="${file#$BUILD_DIR/}"
                BACKUP_PATH="$BACKUP_DIR/$RELATIVE_PATH"
                mkdir -p "$(dirname "$BACKUP_PATH")"
                if cp "$file" "$BACKUP_PATH" 2>/dev/null; then
                    echo -e "  ${GREEN}✓ 已备份: $(basename "$file")${NC}"
                    BACKUP_COUNT=$((BACKUP_COUNT + 1))
                fi
            fi
        done <<< "$EXTENDED_FILES"
        if [ "$BACKUP_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓ 扩展词库文件备份完成（共 $BACKUP_COUNT 个文件）${NC}"
        fi
    fi
    
    echo -e "${YELLOW}正在删除 build 目录...${NC}"
    rm -rf "$BUILD_DIR"
    echo -e "${GREEN}✓ build 目录已删除${NC}"
else
    echo -e "${YELLOW}build 目录不存在，跳过删除步骤${NC}"
fi

# 链接 Rime 配置文件到系统目录
link_rime_config() {
    echo -e "${CYAN}检查系统 Rime 配置链接...${NC}"
    
    # 目标路径列表
    local targets=(
        "$HOME/.config/ibus/rime"
        "$HOME/.var/app/org.fcitx.Fcitx5/data/fcitx5/rime"
        "$HOME/.local/share/fcitx5/rime"
        "$HOME/Library/Rime"
    )
    
    for target in "${targets[@]}"; do
        # 检查目标目录的父目录是否存在（判断是否安装了对应的框架）
        if [ -d "$(dirname "$target")" ]; then
            # 检查是否已经是正确的软链接
            if [ -L "$target" ]; then
                local current_src=$(readlink "$target")
                # 简单检查链接目标是否匹配
                if [[ "$current_src" == "$RIME_DIR" ]]; then
                   echo -e "  ${GREEN}✓ [已链接] $target${NC}"
                   continue
                fi
            fi
            
            # 如果存在但不是我们想要的，先备份
            if [ -e "$target" ]; then
                local backup_path="${target}.backup.$(date +%Y%m%d_%H%M%S)"
                echo -e "  ${YELLOW}⚠ 发现现有配置，备份至: $backup_path${NC}"
                mv "$target" "$backup_path"
            fi
            
            # 创建软链接
            echo -e "  ${YELLOW}创建链接: $target -> $RIME_DIR${NC}"
            ln -s "$RIME_DIR" "$target"
        fi
    done
    echo ""
}

# 检查并自动下载 jaroomaji 词库（如果已启用但缺少文件）
check_jaroomaji_files() {
    local jaroomaji_enabled=false
    local missing_files=0
    
    # 检查是否在 default.custom.yaml 或 default.yaml 中启用了 jaroomaji
    if [ -f "$RIME_DIR/default.custom.yaml" ]; then
        if grep -q "^\s*-\s*schema:\s*jaroomaji" "$RIME_DIR/default.custom.yaml" 2>/dev/null; then
            jaroomaji_enabled=true
        fi
    fi
    
    if [ "$jaroomaji_enabled" = false ] && [ -f "$RIME_DIR/default.yaml" ]; then
        if grep -q "^\s*-\s*schema:\s*jaroomaji" "$RIME_DIR/default.yaml" 2>/dev/null; then
            jaroomaji_enabled=true
        fi
    fi
    
    if [ "$jaroomaji_enabled" = false ]; then
        return 0  # jaroomaji 未启用，无需检查
    fi
    
    # jaroomaji 已启用，检查必要的词库文件
    echo -e "${CYAN}检查 jaroomaji 词库文件...${NC}"
    
    # 需要检查的文件列表（与 manage_jaroomaji.sh 中的 FILES 数组一致）
    local required_files=(
        "jaroomaji.dict.yaml"
        "jaroomaji.kana_kigou.dict.yaml"
        "jaroomaji.mozc.dict.yaml"
        "jaroomaji.jmdict.dict.yaml"
        "jaroomaji.mozcemoji.dict.yaml"
        "jaroomaji.kanjidic2.dict.yaml"
    )
    
    # 检查每个文件是否存在
    for file in "${required_files[@]}"; do
        if [ ! -f "$RIME_DIR/$file" ]; then
            missing_files=$((missing_files + 1))
            echo -e "${YELLOW}  ✗ 缺失: $file${NC}"
        fi
    done
    
    # 如果缺少文件，自动下载
    if [ "$missing_files" -gt 0 ]; then
        echo -e "${YELLOW}⚠ 检测到 $missing_files 个 jaroomaji 词库文件缺失${NC}"
        echo -e "${CYAN}正在自动下载缺失的文件...${NC}"
        echo ""
        
        # 调用 manage_jaroomaji.sh 的下载功能
        local script_dir="$(cd "$(dirname "$0")" && pwd)"
        local manage_script="$script_dir/manage_jaroomaji.sh"
        
        if [ -f "$manage_script" ]; then
            # 使用 manage_jaroomaji.sh 的下载逻辑
            local raw_base_url="https://raw.githubusercontent.com/lazyfoxchan/rime-jaroomaji/master"
            local curl_opts="-sSLf"
            
            # 检测系统类型并设置 curl 选项
            if [ "$(uname -s)" = "Darwin" ]; then
                if command -v /opt/homebrew/opt/curl/bin/curl >/dev/null 2>&1; then
                    curl_cmd="/opt/homebrew/opt/curl/bin/curl $curl_opts"
                elif command -v /usr/local/opt/curl/bin/curl >/dev/null 2>&1; then
                    curl_cmd="/usr/local/opt/curl/bin/curl $curl_opts"
                else
                    curl_cmd="curl $curl_opts -k"
                fi
            else
                curl_cmd="curl $curl_opts"
            fi
            
            # 下载缺失的文件
            local downloaded=0
            for file in "${required_files[@]}"; do
                if [ ! -f "$RIME_DIR/$file" ]; then
                    local url="$raw_base_url/$file"
                    echo -e "${CYAN}  下载中: $file${NC}"
                    if eval "$curl_cmd \"$url\" -o \"$RIME_DIR/$file\"" 2>/dev/null; then
                        echo -e "${GREEN}  ✓ $file 下载成功${NC}"
                        downloaded=$((downloaded + 1))
                    else
                        # 如果第一次失败，尝试使用 -k 选项（macOS SSL 问题）
                        if [ "$(uname -s)" = "Darwin" ] && ! echo "$curl_cmd" | grep -q " -k"; then
                            if curl -sSLf -k "$url" -o "$RIME_DIR/$file" 2>/dev/null; then
                                echo -e "${GREEN}  ✓ $file 下载成功（使用跳过 SSL 验证）${NC}"
                                downloaded=$((downloaded + 1))
                            else
                                echo -e "${RED}  ✗ $file 下载失败${NC}"
                            fi
                        else
                            echo -e "${RED}  ✗ $file 下载失败${NC}"
                        fi
                    fi
                fi
            done
            
            if [ "$downloaded" -gt 0 ]; then
                echo -e "${GREEN}✓ jaroomaji 词库文件下载完成（共 $downloaded 个文件）${NC}"
                echo ""
            else
                echo -e "${YELLOW}⚠ jaroomaji 词库文件下载失败，请检查网络连接${NC}"
                echo ""
            fi
        else
            echo -e "${YELLOW}⚠ 未找到 manage_jaroomaji.sh，无法自动下载${NC}"
            echo ""
        fi
    else
        echo -e "${GREEN}✓ jaroomaji 词库文件完整${NC}"
        echo ""
    fi
}

# 建立软链接
link_rime_config

# 执行检查
check_jaroomaji_files

echo ""
echo -e "${BLUE}开始重新编译...${NC}"
echo ""

# 检测系统类型
OS_TYPE=$(uname -s)
DEPLOY_SUCCESS=false

# macOS (Squirrel)
if [ "$OS_TYPE" = "Darwin" ]; then
    echo -e "${YELLOW}检测到 macOS，使用 Squirrel 部署方式${NC}"
    echo ""
    
    # 方法1: 使用 Squirrel 的部署命令
    SQUIRREL_APP="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
    if [ -f "$SQUIRREL_APP" ]; then
        echo -e "${YELLOW}运行: Squirrel --reload${NC}"
        echo ""
        if "$SQUIRREL_APP" --reload 2>&1; then
            echo ""
            echo -e "${GREEN}✓ Squirrel 配置已重新加载${NC}"
            DEPLOY_SUCCESS=true
        else
            echo -e "${YELLOW}⚠ Squirrel --reload 执行完成（可能需要在设置中手动重新部署）${NC}"
            DEPLOY_SUCCESS=true
        fi
    else
        echo -e "${YELLOW}⚠ 未找到 Squirrel.app${NC}"
        echo -e "${CYAN}请手动在 Squirrel 设置中点击「重新部署」${NC}"
        echo ""
        echo -e "${YELLOW}或者使用以下方法:${NC}"
        echo -e "  1. 打开系统设置 > 键盘 > 输入法"
        echo -e "  2. 找到「日本語ローマ字」或「Rime」"
        echo -e "  3. 右键点击 > 重新部署"
        DEPLOY_SUCCESS=true  # 不视为错误，只是需要手动操作
    fi
    
    # 方法2: 使用 rime_deployer (如果通过 Homebrew 安装)
    if [ "$DEPLOY_SUCCESS" = false ] && command -v rime_deployer &> /dev/null; then
        echo -e "${YELLOW}运行: rime_deployer --build $RIME_DIR${NC}"
        echo ""
        
        LOG_FILE="/tmp/rime_build_$(date +%Y%m%d_%H%M%S).log"
        rime_deployer --build "$RIME_DIR" 2>&1 | tee "$LOG_FILE"
        COMPILE_EXIT_CODE=${PIPESTATUS[0]}
        
        echo ""
        
        if [ "$COMPILE_EXIT_CODE" -eq 0 ]; then
            ERROR_COUNT=$(grep -c "error building config\|unresolved dependency\|ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
            SCHEMA_RESULT=$(grep "finished updating schemas" "$LOG_FILE" 2>/dev/null | tail -1)
            
            if [ "$ERROR_COUNT" -eq 0 ] && [ -n "$SCHEMA_RESULT" ]; then
                echo -e "${GREEN}✓ 编译完成！${NC}"
                SUCCESS_COUNT=$(echo "$SCHEMA_RESULT" | sed -n 's/.*finished updating schemas: \([0-9]*\) success.*/\1/p' | head -1)
                FAILURE_COUNT=$(echo "$SCHEMA_RESULT" | sed -n 's/.*\([0-9]*\) failure.*/\1/p' | head -1)
                SUCCESS_COUNT=${SUCCESS_COUNT:-0}
                FAILURE_COUNT=${FAILURE_COUNT:-0}
                echo -e "${GREEN}  方案编译: ${SUCCESS_COUNT} 成功, ${FAILURE_COUNT} 失败${NC}"
                DEPLOY_SUCCESS=true
            else
                echo -e "${YELLOW}⚠ 编译完成，但检测到可能的错误${NC}"
                DEPLOY_SUCCESS=true
            fi
        fi
    fi

# Linux (Fcitx5)
elif [ "$OS_TYPE" = "Linux" ]; then
    echo -e "${YELLOW}检测到 Linux，使用 Fcitx5 部署方式${NC}"
    echo ""
    
    if command -v rime_deployer &> /dev/null; then
        echo -e "${YELLOW}运行: rime_deployer --build $RIME_DIR${NC}"
        echo ""
        
        # 编译并保存日志
        LOG_FILE="/tmp/rime_build_$(date +%Y%m%d_%H%M%S).log"
        rime_deployer --build "$RIME_DIR" 2>&1 | tee "$LOG_FILE"
        COMPILE_EXIT_CODE=${PIPESTATUS[0]}
        
        echo ""
        
        # 检查编译结果
        if [ "$COMPILE_EXIT_CODE" -eq 0 ]; then
            # 检查日志中的错误
            ERROR_COUNT=$(grep -c "error building config\|unresolved dependency\|ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
            ERROR_COUNT=$(echo "$ERROR_COUNT" | tr -d '\n' | head -1)
            ERROR_COUNT=${ERROR_COUNT:-0}
            SCHEMA_RESULT=$(grep "finished updating schemas" "$LOG_FILE" 2>/dev/null | tail -1)
            
            if [ "$ERROR_COUNT" -eq 0 ] && [ -n "$SCHEMA_RESULT" ]; then
                echo -e "${GREEN}✓ 编译完成！${NC}"
                
                # 显示方案编译结果
                if echo "$SCHEMA_RESULT" | grep -q "finished updating schemas"; then
                    # 使用 sed 提取数字，兼容性更好
                    SUCCESS_COUNT=$(echo "$SCHEMA_RESULT" | sed -n 's/.*finished updating schemas: \([0-9]*\) success.*/\1/p' | head -1)
                    FAILURE_COUNT=$(echo "$SCHEMA_RESULT" | sed -n 's/.*\([0-9]*\) failure.*/\1/p' | head -1)
                    SUCCESS_COUNT=${SUCCESS_COUNT:-0}
                    FAILURE_COUNT=${FAILURE_COUNT:-0}
                    echo -e "${GREEN}  方案编译: ${SUCCESS_COUNT} 成功, ${FAILURE_COUNT} 失败${NC}"
                fi
                
                DEPLOY_SUCCESS=true
            else
                echo -e "${YELLOW}⚠ 编译完成，但检测到可能的错误${NC}"
                if [ "$ERROR_COUNT" -gt 0 ]; then
                    echo -e "${YELLOW}  发现 $ERROR_COUNT 个错误${NC}"
                    echo ""
                    echo -e "${YELLOW}关键错误信息：${NC}"
                    grep -E "error building config|unresolved dependency|ERROR" "$LOG_FILE" 2>/dev/null | tail -5 | while read line; do
                        echo -e "  ${RED}$line${NC}"
                    done
                fi
                DEPLOY_SUCCESS=true  # 即使有错误也继续，因为可能只是某些方案失败
            fi
            
            # 恢复扩展词库文件（如果备份存在且编译后的文件不存在）
            if [ -d "$BACKUP_DIR" ] && [ -d "$BUILD_DIR" ]; then
                RESTORED_FILES=$(find "$BACKUP_DIR" -type f 2>/dev/null)
                if [ -n "$RESTORED_FILES" ]; then
                    echo ""
                    echo -e "${YELLOW}检查并恢复扩展词库文件...${NC}"
                    RESTORE_COUNT=0
                    while IFS= read -r backup_file; do
                        if [ -f "$backup_file" ]; then
                            RELATIVE_PATH="${backup_file#$BACKUP_DIR/}"
                            TARGET_FILE="$BUILD_DIR/$RELATIVE_PATH"
                            
                            # 如果目标文件不存在，则从备份恢复
                            if [ ! -f "$TARGET_FILE" ]; then
                                mkdir -p "$(dirname "$TARGET_FILE")"
                                if cp "$backup_file" "$TARGET_FILE" 2>/dev/null; then
                                    echo -e "  ${GREEN}✓ 已恢复: $(basename "$TARGET_FILE")${NC}"
                                    RESTORE_COUNT=$((RESTORE_COUNT + 1))
                                    EXTENDED_FILES_RESTORED=true
                                fi
                            fi
                        fi
                    done <<< "$RESTORED_FILES"
                    
                    if [ "$RESTORE_COUNT" -gt 0 ]; then
                        echo -e "${GREEN}✓ 扩展词库文件恢复完成（共 $RESTORE_COUNT 个文件）${NC}"
                    else
                        echo -e "${YELLOW}  扩展词库文件已存在或无需恢复${NC}"
                    fi
                fi
                
                # 清理临时备份目录
                rm -rf "$BACKUP_DIR" 2>/dev/null
            fi
            
            # 如果编译后仍然缺少扩展词库文件，尝试从永久备份目录恢复
            if [ -d "$BUILD_DIR" ]; then
                PERMANENT_BACKUP_DIR="$RIME_DIR/resources"
                if [ -d "$PERMANENT_BACKUP_DIR" ]; then
                    # 检查 build 目录中是否缺少扩展词库文件
                    EXPECTED_FILES=("sbzr.extended.table.bin" "sbzr.extended.prism.bin" "sbzr.extended.reverse.bin")
                    MISSING_COUNT=0
                    for expected_file in "${EXPECTED_FILES[@]}"; do
                        if [ ! -f "$BUILD_DIR/$expected_file" ]; then
                            MISSING_COUNT=$((MISSING_COUNT + 1))
                        fi
                    done
                    
                    # 如果有缺失的文件，从永久备份目录恢复
                    if [ "$MISSING_COUNT" -gt 0 ]; then
                        PERMANENT_BACKUP_FILES=$(find "$PERMANENT_BACKUP_DIR" -name "*.extended.*" -type f 2>/dev/null)
                        if [ -n "$PERMANENT_BACKUP_FILES" ]; then
                            echo ""
                            echo -e "${YELLOW}从永久备份目录恢复扩展词库文件...${NC}"
                            RESTORE_COUNT=0
                            while IFS= read -r backup_file; do
                                if [ -f "$backup_file" ]; then
                                    FILENAME=$(basename "$backup_file")
                                    TARGET_FILE="$BUILD_DIR/$FILENAME"
                                    if [ ! -f "$TARGET_FILE" ]; then
                                        if cp "$backup_file" "$TARGET_FILE" 2>/dev/null; then
                                            echo -e "  ${GREEN}✓ 已从备份恢复: $FILENAME${NC}"
                                            RESTORE_COUNT=$((RESTORE_COUNT + 1))
                                        fi
                                    fi
                                fi
                            done <<< "$PERMANENT_BACKUP_FILES"
                            if [ "$RESTORE_COUNT" -gt 0 ]; then
                                echo -e "${GREEN}✓ 扩展词库文件恢复完成（共 $RESTORE_COUNT 个文件）${NC}"
                            fi
                        fi
                    fi
                fi
                
                # 恢复 sbpy/sbyp 拼音反查文件（如果缺失）
                if [ -d "$BUILD_DIR" ]; then
                    BACKUP_BUILD_DIR="$PERMANENT_BACKUP_DIR/build"
                    if [ -d "$BACKUP_BUILD_DIR" ]; then
                        # 检查 build 目录中是否缺少 sbpy/sbyp 文件
                        EXPECTED_SBPY_FILES=("sbpy.base.table.bin" "sbpy.ext.table.bin" "sbpy.tencent.table.bin" "sbpy.table.bin" "sbpy.prism.bin" "sbpy.reverse.bin" "sbyp.prism.bin")
                        MISSING_SBPY_COUNT=0
                        for expected_file in "${EXPECTED_SBPY_FILES[@]}"; do
                            if [ ! -f "$BUILD_DIR/$expected_file" ]; then
                                MISSING_SBPY_COUNT=$((MISSING_SBPY_COUNT + 1))
                            fi
                        done
                        
                        # 如果有缺失的文件，从备份目录恢复
                        if [ "$MISSING_SBPY_COUNT" -gt 0 ]; then
                            SBPY_BACKUP_FILES=$(find "$BACKUP_BUILD_DIR" -name "sbpy.*.bin" -o -name "sbyp.*.bin" 2>/dev/null)
                            if [ -n "$SBPY_BACKUP_FILES" ]; then
                                echo ""
                                echo -e "${YELLOW}从备份目录恢复拼音反查文件...${NC}"
                                RESTORE_COUNT=0
                                while IFS= read -r backup_file; do
                                    if [ -f "$backup_file" ]; then
                                        FILENAME=$(basename "$backup_file")
                                        TARGET_FILE="$BUILD_DIR/$FILENAME"
                                        if [ ! -f "$TARGET_FILE" ]; then
                                            if cp "$backup_file" "$TARGET_FILE" 2>/dev/null; then
                                                echo -e "  ${GREEN}✓ 已从备份恢复: $FILENAME${NC}"
                                                RESTORE_COUNT=$((RESTORE_COUNT + 1))
                                            fi
                                        fi
                                    fi
                                done <<< "$SBPY_BACKUP_FILES"
                                if [ "$RESTORE_COUNT" -gt 0 ]; then
                                    echo -e "${GREEN}✓ 拼音反查文件恢复完成（共 $RESTORE_COUNT 个文件）${NC}"
                                fi
                            fi
                        fi
                    fi
                    
                    # 恢复 sbyp.schema.yaml（如果缺失）
                    if [ ! -f "$RIME_DIR/sbyp.schema.yaml" ] && [ -f "$PERMANENT_BACKUP_DIR/sbyp.schema.yaml" ]; then
                        echo ""
                        echo -e "${YELLOW}从备份目录恢复 sbyp.schema.yaml...${NC}"
                        if cp "$PERMANENT_BACKUP_DIR/sbyp.schema.yaml" "$RIME_DIR/sbyp.schema.yaml" 2>/dev/null; then
                            echo -e "${GREEN}✓ 已从备份恢复: sbyp.schema.yaml${NC}"
                        fi
                    fi
                fi
            fi
        else
            echo -e "${RED}✗ 编译过程中出现错误（退出码: $COMPILE_EXIT_CODE）${NC}"
            echo -e "${YELLOW}详细日志已保存到: $LOG_FILE${NC}"
            echo ""
            echo -e "${YELLOW}关键错误信息：${NC}"
            grep -E "error building config|unresolved dependency|ERROR" "$LOG_FILE" 2>/dev/null | tail -10 | while read line; do
                echo -e "  ${RED}$line${NC}"
            done
            
            # 即使编译失败，也尝试恢复扩展词库文件
            if [ -d "$BACKUP_DIR" ] && [ -d "$BUILD_DIR" ]; then
                RESTORED_FILES=$(find "$BACKUP_DIR" -type f 2>/dev/null)
                if [ -n "$RESTORED_FILES" ]; then
                    echo ""
                    echo -e "${YELLOW}尝试恢复扩展词库文件...${NC}"
                    RESTORE_COUNT=0
                    while IFS= read -r backup_file; do
                        if [ -f "$backup_file" ]; then
                            RELATIVE_PATH="${backup_file#$BACKUP_DIR/}"
                            TARGET_FILE="$BUILD_DIR/$RELATIVE_PATH"
                            mkdir -p "$(dirname "$TARGET_FILE")"
                            if cp "$backup_file" "$TARGET_FILE" 2>/dev/null; then
                                echo -e "  ${GREEN}✓ 已恢复: $(basename "$TARGET_FILE")${NC}"
                                RESTORE_COUNT=$((RESTORE_COUNT + 1))
                            fi
                        fi
                    done <<< "$RESTORED_FILES"
                    if [ "$RESTORE_COUNT" -gt 0 ]; then
                        echo -e "${GREEN}✓ 扩展词库文件恢复完成（共 $RESTORE_COUNT 个文件）${NC}"
                    fi
                fi
                rm -rf "$BACKUP_DIR" 2>/dev/null
            fi
            
            # 即使编译失败，也尝试恢复 sbpy/sbyp 文件
            if [ -d "$BUILD_DIR" ]; then
                PERMANENT_BACKUP_DIR="$RIME_DIR/resources"
                BACKUP_BUILD_DIR="$PERMANENT_BACKUP_DIR/build"
                if [ -d "$BACKUP_BUILD_DIR" ]; then
                    SBPY_BACKUP_FILES=$(find "$BACKUP_BUILD_DIR" -name "sbpy.*.bin" -o -name "sbyp.*.bin" 2>/dev/null)
                    if [ -n "$SBPY_BACKUP_FILES" ]; then
                        echo ""
                        echo -e "${YELLOW}尝试恢复拼音反查文件...${NC}"
                        RESTORE_COUNT=0
                        while IFS= read -r backup_file; do
                            if [ -f "$backup_file" ]; then
                                FILENAME=$(basename "$backup_file")
                                TARGET_FILE="$BUILD_DIR/$FILENAME"
                                if [ ! -f "$TARGET_FILE" ]; then
                                    if cp "$backup_file" "$TARGET_FILE" 2>/dev/null; then
                                        echo -e "  ${GREEN}✓ 已恢复: $FILENAME${NC}"
                                        RESTORE_COUNT=$((RESTORE_COUNT + 1))
                                    fi
                                fi
                            fi
                        done <<< "$SBPY_BACKUP_FILES"
                        if [ "$RESTORE_COUNT" -gt 0 ]; then
                            echo -e "${GREEN}✓ 拼音反查文件恢复完成（共 $RESTORE_COUNT 个文件）${NC}"
                        fi
                    fi
                fi
                
                # 恢复 sbyp.schema.yaml（如果缺失）
                if [ ! -f "$RIME_DIR/sbyp.schema.yaml" ] && [ -f "$PERMANENT_BACKUP_DIR/sbyp.schema.yaml" ]; then
                    echo ""
                    echo -e "${YELLOW}从备份目录恢复 sbyp.schema.yaml...${NC}"
                    if cp "$PERMANENT_BACKUP_DIR/sbyp.schema.yaml" "$RIME_DIR/sbyp.schema.yaml" 2>/dev/null; then
                        echo -e "${GREEN}✓ 已从备份恢复: sbyp.schema.yaml${NC}"
                    fi
                fi
            fi
        fi
        
        # 保存日志文件路径供后续查看
        echo "$LOG_FILE" > /tmp/rime_last_build_log.txt 2>/dev/null
    else
        echo -e "${RED}错误：未找到 rime_deployer 命令${NC}"
        echo -e "${YELLOW}请确保已安装 fcitx5-rime${NC}"
        echo -e "${YELLOW}安装命令: sudo apt install fcitx5-rime${NC}"
    fi
fi

if [ "$DEPLOY_SUCCESS" = false ]; then
    echo ""
    echo -e "${YELLOW}⚠ 自动部署失败，请手动重新部署配置${NC}"
    echo -e "${CYAN}macOS: 在 Squirrel 设置中点击「重新部署」${NC}"
    echo -e "${CYAN}Linux: 在 Fcitx5 设置中点击「重新部署」${NC}"
fi

echo ""
echo -e "${BLUE}编译结果统计：${NC}"

# 检查 build 目录
if [ -d "$BUILD_DIR" ]; then
    BUILD_SIZE=$(du -sh "$BUILD_DIR" 2>/dev/null | cut -f1)
    BIN_COUNT=$(find "$BUILD_DIR" -name "*.bin" 2>/dev/null | wc -l)
    SCHEMA_COUNT=$(find "$BUILD_DIR" -name "*.schema.yaml" 2>/dev/null | wc -l)
    
    echo -e "  ${GREEN}build 目录大小: $BUILD_SIZE${NC}"
    echo -e "  ${GREEN}二进制文件数量: $BIN_COUNT${NC}"
    echo -e "  ${GREEN}配置文件数量: $SCHEMA_COUNT${NC}"
    
    # 列出主要的二进制文件
    echo ""
    echo -e "${BLUE}主要编译文件：${NC}"
    # 优先显示扩展词库文件
    EXTENDED_BINS=$(find "$BUILD_DIR" -name "*.extended.*" -type f 2>/dev/null)
    if [ -n "$EXTENDED_BINS" ]; then
        echo "$EXTENDED_BINS" | while IFS= read -r file; do
            if [ -f "$file" ]; then
                SIZE=$(ls -lh "$file" 2>/dev/null | awk '{print $5}')
                echo -e "  ${GREEN}$SIZE $(basename "$file")${NC}"
            fi
        done
    fi
    # 然后显示其他二进制文件
    find "$BUILD_DIR" -name "*.bin" -type f ! -name "*.extended.*" -exec ls -lh {} \; 2>/dev/null | \
        awk '{printf "  %s %s\n", $5, $9}' | head -10
else
    echo -e "${RED}  build 目录未创建，编译可能失败${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
if [ "$DEPLOY_SUCCESS" = true ]; then
    echo -e "${GREEN}重建完成！${NC}"
else
    echo -e "${YELLOW}build 目录已清理，请手动重新部署${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo ""

# 根据系统类型提供不同的提示
OS_TYPE=$(uname -s)
if [ "$OS_TYPE" = "Darwin" ]; then
    echo -e "${YELLOW}macOS 提示：${NC}"
    echo -e "${CYAN}  1. 打开系统设置 > 键盘 > 输入法${NC}"
    echo -e "${CYAN}  2. 找到「日本語ローマ字」或「Rime」${NC}"
    echo -e "${CYAN}  3. 右键点击 > 重新部署${NC}"
    echo ""
    echo -e "${CYAN}  或者重启应用以触发自动重新部署${NC}"
else
    echo -e "${YELLOW}提示：如果输入法未正常工作，请重启 Fcitx5${NC}"
    echo -e "${YELLOW}重启命令: killall fcitx5 && fcitx5 &${NC}"
fi
