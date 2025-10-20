# Sources Chat Crash 與 Ask 頁面問題分析報告

**日期**: 2025-10-20
**問題類型**: Crash 分析、功能澄清
**分析者**: Claude Code

---

## 執行摘要

分析了兩個使用者報告的問題：
1. **Sources chat 容易 crash** - 找到 4 個潛在的根本原因
2. **Ask 頁面無法上傳檔案** - 這是功能誤解，Ask 頁面設計上不支援檔案上傳

### 關鍵發現

| 問題 | 嚴重性 | 狀態 | 根本原因 |
|------|--------|------|----------|
| Context 建立時錯誤處理不足 | 🟡 高 | 未修復 | 靜默失敗，沒有詳細日誌 |
| get_insights() 異常傳播 | 🟡 高 | 未修復 | DatabaseOperationError 中斷整個流程 |
| full_text 大小/格式問題 | 🟢 中 | 未修復 | 未處理 None 或超大內容 |
| API 超時設定不足 | 🟢 中 | 未修復 | 30 秒可能不夠處理多個 sources |
| Ask 頁面無上傳功能 | ℹ️ 資訊 | 設計如此 | 不是 bug，是功能設計 |

---

## 問題 1：Sources Chat Crash 分析

### 1.1 錯誤處理不完整

**位置**: `api/routers/context.py:34-57`

**問題代碼**:
```python
try:
    # Add table prefix if not present
    full_source_id = (
        source_id
        if source_id.startswith("source:")
        else f"source:{source_id}"
    )

    try:
        source = await Source.get(full_source_id)
    except Exception as e:
        continue  # ❌ 靜默失敗

    if "insights" in status:
        source_context = await source.get_context(context_size="short")
        context_data["source"].append(source_context)
        total_content += str(source_context)
    elif "full content" in status:
        source_context = await source.get_context(context_size="long")
        context_data["source"].append(source_context)
        total_content += str(source_context)
except Exception as e:
    logger.warning(f"Error processing source {source_id}: {str(e)}")
    continue
```

**問題**:
1. **靜默失敗**: `Source.get()` 失敗時只是 `continue`，沒有記錄原因
2. **使用者無感知**: 使用者不知道哪個 source 載入失敗
3. **`get_context()` 沒有獨立錯誤處理**: 如果這裡出錯，會被外層 catch 並跳過整個 source

**影響**:
- 當單個 source 有問題時，整個 source 被跳過
- 無法追蹤哪個 source 有問題
- 使用者以為 context 完整，但實際缺少內容

**發生場景**:
- Source 被刪除但引用仍存在
- Source 資料格式損壞
- 資料庫連線不穩定
- Insights 查詢失敗

### 1.2 get_insights() 異常傳播問題

**位置**: `open_notebook/domain/notebook.py:181-193`

**問題代碼**:
```python
async def get_insights(self) -> List[SourceInsight]:
    try:
        result = await repo_query(
            """
            SELECT * FROM source_insight WHERE source=$id
            """,
            {"id": ensure_record_id(self.id)},
        )
        return [SourceInsight(**insight) for insight in result]
    except Exception as e:
        logger.error(f"Error fetching insights for source {self.id}: {str(e)}")
        logger.exception(e)
        raise DatabaseOperationError("Failed to fetch insights for source")  # ❌ 拋出異常
```

**問題**:
1. **拋出異常而非返回空列表**: 當 insights 載入失敗時，整個 source context 建立失敗
2. **資料格式錯誤也會失敗**: `SourceInsight(**insight)` 如果資料格式不匹配會拋出 ValidationError
3. **沒有降級策略**: 應該允許 source 在沒有 insights 的情況下仍能使用

**影響**:
- 單個 source 的 insights 問題導致整個聊天失敗
- 使用者看到 crash 而不是部分內容
- 無法使用有問題的 source

**建議修改**:
```python
async def get_insights(self) -> List[SourceInsight]:
    try:
        result = await repo_query(
            """
            SELECT * FROM source_insight WHERE source=$id
            """,
            {"id": ensure_record_id(self.id)},
        )
        insights = []
        for insight in result:
            try:
                insights.append(SourceInsight(**insight))
            except Exception as e:
                logger.warning(f"Skipping invalid insight for source {self.id}: {str(e)}")
                continue
        return insights
    except Exception as e:
        logger.error(f"Error fetching insights for source {self.id}: {str(e)}")
        # Return empty list instead of raising
        return []
```

### 1.3 full_text 處理問題

**位置**: `open_notebook/domain/notebook.py:150-163`

**問題代碼**:
```python
async def get_context(
    self, context_size: Literal["short", "long"] = "short"
) -> Dict[str, Any]:
    insights_list = await self.get_insights()
    insights = [insight.model_dump() for insight in insights_list]
    if context_size == "long":
        return dict(
            id=self.id,
            title=self.title,
            insights=insights,
            full_text=self.full_text,  # ❌ 可能是 None 或超大
        )
    else:
        return dict(id=self.id, title=self.title, insights=insights)
```

**問題**:
1. **`full_text` 可能是 None**: 沒有處理 None 的情況
2. **`full_text` 可能超大**: 沒有大小限制，可能導致記憶體問題或序列化超時
3. **沒有截斷機制**: 應該提供選項截斷超長內容

**影響場景**:
- 上傳大型 PDF 檔案（例如書籍、長篇研究報告）
- 抓取長篇網頁內容
- 大量 insights 累積

**建議修改**:
```python
async def get_context(
    self, context_size: Literal["short", "long"] = "short"
) -> Dict[str, Any]:
    insights_list = await self.get_insights()
    insights = [insight.model_dump() for insight in insights_list]

    if context_size == "long":
        # Limit full_text size to prevent memory issues
        MAX_FULL_TEXT_SIZE = 100000  # ~100K characters
        full_text = self.full_text or ""
        if len(full_text) > MAX_FULL_TEXT_SIZE:
            full_text = full_text[:MAX_FULL_TEXT_SIZE] + "\n\n[Content truncated due to size limit]"
            logger.warning(f"Truncated full_text for source {self.id} from {len(self.full_text)} to {MAX_FULL_TEXT_SIZE} chars")

        return dict(
            id=self.id,
            title=self.title,
            insights=insights,
            full_text=full_text,
        )
    else:
        return dict(id=self.id, title=self.title, insights=insights)
```

### 1.4 API 超時問題

**位置**: `api/client.py:18`

**問題代碼**:
```python
def __init__(self, base_url: Optional[str] = None):
    self.base_url = base_url or os.getenv("API_BASE_URL", "http://127.0.0.1:5055")
    self.timeout = 30.0  # ❌ 固定 30 秒
```

**問題**:
1. **固定 30 秒超時**: 對於有多個 sources 的 notebook，可能不夠
2. **沒有根據操作類型調整**: Context 建立需要的時間遠超普通 API 呼叫

**計算範例**:
```
假設一個 notebook 有 10 個 sources:
- 每個 source 載入: ~1-2 秒
- 每個 source 的 insights 查詢: ~0.5-1 秒
- get_context 呼叫: ~0.5 秒
- 總計: 10 * (2 + 1 + 0.5) = 35 秒 > 30 秒超時
```

**建議修改**:
```python
def _make_request(
    self, method: str, endpoint: str, timeout: Optional[float] = None, **kwargs
) -> Dict:
    """Make HTTP request to the API."""
    url = f"{self.base_url}{endpoint}"

    # Dynamic timeout based on endpoint
    if timeout is None:
        if "/context" in endpoint:
            request_timeout = 120.0  # 2 minutes for context operations
        else:
            request_timeout = self.timeout
    else:
        request_timeout = timeout

    # ... rest of the method
```

---

## 問題 2：Ask 頁面無法上傳檔案

### 2.1 功能設計澄清

**使用者問題**: "無法 ask 上傳文件"

**實際情況**: **Ask 頁面沒有設計檔案上傳功能**

**檔案**: `pages/3_🔍_Ask_and_Search.py`

**Ask 頁面功能**:
```python
with ask_tab:
    st.subheader("Ask Your Knowledge Base (beta)")
    st.caption(
        "The LLM will answer your query based on the documents in your knowledge base."
    )
    question = st.text_input("Question", "")  # ✅ 只有文字輸入
    # ❌ 沒有 st.file_uploader()
```

### 2.2 正確的檔案上傳位置

**檔案上傳功能位於**:

#### 位置 1: Notebooks 頁面 (主要位置)
**檔案**: `pages/stream_app/source.py:24-146`

```python
@st.dialog("Add a Source", width="large")
def add_source(notebook_id):
    source_type = st.radio("Type", ["Link", "Upload", "Text"])

    if source_type == "Upload":
        source_file = st.file_uploader("Upload")  # ✅ 檔案上傳器

        if source_file is not None:
            # 處理檔案上傳
            file_name = source_file.name
            new_path = os.path.join(UPLOADS_FOLDER, file_name)

            # 保存檔案
            with open(new_path, "wb") as f:
                f.write(source_file.getbuffer())

            # 創建 source
            sources_service.create_source(
                notebook_id=notebook_id,
                source_type="upload",
                file_path=new_path,
                ...
            )
```

**使用方式**:
1. 前往 **Notebooks** 頁面
2. 選擇或建立一個 notebook
3. 點擊 **Add Source** 按鈕
4. 選擇 **Upload** 類型
5. 使用 file uploader 上傳檔案

### 2.3 Ask vs. Source Upload 的差異

| 功能 | Ask 頁面 | Notebooks 頁面 (Add Source) |
|------|----------|---------------------------|
| **目的** | 查詢已存在的知識庫 | 添加新內容到知識庫 |
| **輸入** | 文字問題 | Link, Upload, Text |
| **檔案上傳** | ❌ 不支援 | ✅ 支援 |
| **處理方式** | 即時回答 | 後台處理、embedding、insights |
| **使用場景** | 想問問題時 | 想新增資料時 |

### 2.4 使用者工作流程建議

**正確的工作流程**:
```
1. 上傳文件 (Notebooks 頁面)
   └─> 選擇 Notebook
   └─> Add Source → Upload → 選擇檔案
   └─> 等待處理完成 (embedding, insights)

2. 與文件聊天 (Notebooks 頁面)
   └─> 選擇剛才上傳的 source
   └─> 選擇 context (insights or full content)
   └─> 在 chat 中提問

3. 查詢知識庫 (Ask 頁面)
   └─> 輸入問題
   └─> 系統自動搜尋所有 notebooks 中的內容
   └─> 獲得答案
```

**常見誤解**:
- ❌ "在 Ask 頁面上傳檔案後馬上問問題"
- ✅ "先在 Notebooks 上傳並處理，之後再用 Ask 查詢"

---

## 推薦修復方案

### 優先級 P0 (立即修復)

#### 1. 改善 get_insights() 錯誤處理
**目標**: 讓 insights 失敗不會導致整個 source 無法使用

**修改檔案**: `open_notebook/domain/notebook.py`

```python
async def get_insights(self) -> List[SourceInsight]:
    """
    Fetch insights for this source.
    Returns empty list on failure instead of raising exception.
    """
    try:
        result = await repo_query(
            """
            SELECT * FROM source_insight WHERE source=$id
            """,
            {"id": ensure_record_id(self.id)},
        )

        insights = []
        for insight_data in result:
            try:
                insights.append(SourceInsight(**insight_data))
            except Exception as validation_error:
                logger.warning(
                    f"Skipping invalid insight for source {self.id}: {str(validation_error)}"
                )
                continue

        return insights

    except Exception as e:
        logger.error(f"Error fetching insights for source {self.id}: {str(e)}")
        logger.exception(e)
        # Return empty list instead of raising - allows source to be used without insights
        return []
```

**效果**:
- ✅ Source 即使沒有 insights 也能使用
- ✅ 個別損壞的 insight 不會影響其他 insights
- ✅ 使用者可以繼續工作，不會看到 crash

#### 2. Context 建立的 Fallback 機制
**目標**: 當 full context 失敗時降級到 short context

**修改檔案**: `api/routers/context.py`

```python
# 在 line 47-54 處修改
if "insights" in status:
    try:
        source_context = await source.get_context(context_size="short")
        context_data["source"].append(source_context)
        total_content += str(source_context)
    except Exception as e:
        logger.error(f"Error getting short context for source {source_id}: {str(e)}")
        # Include minimal info so user knows something went wrong
        context_data["source"].append({
            "id": source.id,
            "title": source.title or "Untitled",
            "error": "Failed to load insights"
        })

elif "full content" in status:
    try:
        source_context = await source.get_context(context_size="long")
        context_data["source"].append(source_context)
        total_content += str(source_context)
    except Exception as e:
        logger.error(f"Error getting full context for source {source_id}: {str(e)}")
        # Try fallback to short context
        try:
            logger.info(f"Attempting fallback to short context for {source_id}")
            source_context = await source.get_context(context_size="short")
            context_data["source"].append(source_context)
            total_content += str(source_context)
            logger.info(f"Fallback successful for {source_id}")
        except Exception as fallback_error:
            logger.error(f"Fallback also failed for {source_id}: {str(fallback_error)}")
            # Include error info
            context_data["source"].append({
                "id": source.id,
                "title": source.title or "Untitled",
                "error": "Failed to load content"
            })
```

**效果**:
- ✅ Full content 失敗時自動嘗試 short context
- ✅ 完全失敗時至少顯示 source 標題和錯誤訊息
- ✅ 使用者知道哪個 source 有問題

### 優先級 P1 (重要但非緊急)

#### 3. 添加 full_text 大小限制
**目標**: 防止超大文件導致記憶體或序列化問題

**修改檔案**: `open_notebook/domain/notebook.py`

```python
# 添加常數
MAX_FULL_TEXT_SIZE = 100000  # ~100K characters

async def get_context(
    self, context_size: Literal["short", "long"] = "short"
) -> Dict[str, Any]:
    insights_list = await self.get_insights()
    insights = [insight.model_dump() for insight in insights_list]

    if context_size == "long":
        # Handle None and limit size
        full_text = self.full_text or ""
        original_size = len(full_text)

        if original_size > MAX_FULL_TEXT_SIZE:
            full_text = full_text[:MAX_FULL_TEXT_SIZE] + "\n\n[Content truncated due to size limit]"
            logger.warning(
                f"Truncated full_text for source {self.id}: "
                f"{original_size} → {MAX_FULL_TEXT_SIZE} chars"
            )

        return dict(
            id=self.id,
            title=self.title,
            insights=insights,
            full_text=full_text,
        )
    else:
        return dict(id=self.id, title=self.title, insights=insights)
```

**效果**:
- ✅ 防止超大文件導致系統 crash
- ✅ 保留大部分內容（100K 字符約 25K tokens）
- ✅ 明確告知使用者內容被截斷

#### 4. 增加 Context API 超時時間
**目標**: 給予足夠時間處理多個 sources

**修改檔案**: `api/client.py`

```python
def _make_request(
    self, method: str, endpoint: str, timeout: Optional[float] = None, **kwargs
) -> Dict:
    """Make HTTP request to the API."""
    url = f"{self.base_url}{endpoint}"

    # Dynamic timeout based on endpoint type
    if timeout is None:
        if "/context" in endpoint:
            # Context operations need more time for multiple sources
            request_timeout = 120.0  # 2 minutes
        elif "/sources" in endpoint and method == "POST":
            # Source creation (with processing) needs more time
            request_timeout = 90.0  # 1.5 minutes
        else:
            request_timeout = self.timeout
    else:
        request_timeout = timeout

    # ... rest of method
```

**效果**:
- ✅ Context 建立有 2 分鐘處理時間（約可處理 20+ sources）
- ✅ 其他 API 保持 30 秒超時（不影響效能）
- ✅ 可手動覆寫超時設定

### 優先級 P2 (長期改進)

#### 5. 添加 UI 錯誤提示
**目標**: 讓使用者知道哪個 source 有問題

**修改檔案**: `pages/stream_app/chat.py`

在 context 顯示區域添加錯誤提示：

```python
# 在 build_context 之後檢查錯誤
context = build_context(current_notebook.id)

# Check for sources with errors
error_sources = [
    s for s in context.get("source", [])
    if isinstance(s, dict) and s.get("error")
]

if error_sources:
    with st.expander("⚠️ Some sources failed to load", expanded=False):
        st.warning(
            f"{len(error_sources)} source(s) had errors and may not be fully included in context:"
        )
        for error_source in error_sources:
            st.markdown(
                f"- **{error_source.get('title', 'Unknown')}**: {error_source.get('error', 'Unknown error')}"
            )
        st.caption(
            "These sources are partially included. Check the source directly for more details."
        )
```

#### 6. 改進日誌記錄
**目標**: 更容易追蹤問題根源

在各個錯誤處理點添加結構化日誌：

```python
logger.error(
    "Source context loading failed",
    extra={
        "source_id": source_id,
        "notebook_id": notebook_id,
        "context_size": status,
        "error_type": type(e).__name__,
        "error_message": str(e),
    }
)
```

---

## 測試計畫

### 測試場景 1: 損壞的 Source
```
1. 手動修改資料庫，破壞一個 source 的 insights
2. 嘗試在聊天中使用該 source
3. 預期：Chat 不會 crash，顯示錯誤提示，其他 sources 正常工作
```

### 測試場景 2: 超大文件
```
1. 上傳一個大型 PDF (>10MB)
2. 選擇 "full content" context
3. 預期：Content 被截斷到 100K 字符，顯示截斷警告，chat 正常運作
```

### 測試場景 3: 多個 Sources
```
1. 建立一個有 20+ sources 的 notebook
2. 全部選擇 "full content" context
3. 嘗試聊天
4. 預期：Context 建立在 2 分鐘內完成，不會超時
```

### 測試場景 4: 資料庫連線問題
```
1. 暫時停止 SurrealDB
2. 嘗試聊天
3. 重新啟動 SurrealDB
4. 預期：清楚的錯誤訊息，不是神秘的 crash
```

---

## 相關問題連結

- **問題 9**: SurrealDB 端口未暴露導致聊天功能完全失敗 (已修復)
- **問題 8**: 聊天訊息重複提交 (已修復)

---

## 總結

### Sources Chat Crash 的真正原因

不是單一原因，而是**多個弱點的組合**：

1. **❌ 錯誤處理不夠強健** - 單個失敗導致整體失敗
2. **❌ 沒有降級策略** - 無法在部分失敗時繼續運作
3. **❌ 資源管理不當** - 超大內容、超時設定不合理
4. **❌ 使用者反饋不足** - Crash 時沒有明確指出問題

### Ask 頁面的檔案上傳問題

**不是 bug，而是功能設計**：
- Ask 頁面 = 查詢已存在的知識庫
- Notebooks 頁面 = 管理知識庫內容（包括上傳）

需要改進**使用者引導**，讓使用者理解正確的工作流程。

### 建議實施順序

1. **立即**: 修復 `get_insights()` 和 context fallback (P0)
2. **本週**: 添加 full_text 大小限制和超時設定 (P1)
3. **下週**: 改進 UI 錯誤提示和日誌 (P2)
4. **持續**: 監控 crash 日誌，識別其他潛在問題

---

**文件版本**: 1.0
**最後更新**: 2025-10-20 17:30
**下一步**: 實施 P0 修復並測試
