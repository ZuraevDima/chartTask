<script setup>
import { ref, computed } from 'vue'
import * as XLSX from 'xlsx'
import ForceDirectedTree from './components/ForceDirectedTree.vue'

const worlds = ref(null)
const fileName = ref('')
const searchQuery = ref('')

const filteredWorlds = computed(() => {
  if (!worlds.value || !searchQuery.value.trim()) return worlds.value
  
  const q = searchQuery.value.toLowerCase().trim()
  return worlds.value.filter(w => w.name.toLowerCase().includes(q))
})

const clearSearch = () => searchQuery.value = ''

const findHeaderIndex = (headers, re) => {
  for (let i = 0; i < headers.length; i++) {
    const h = String(headers[i] ?? '').trim()
    if (h && re.test(h.toLowerCase())) return i
  }
  return -1
}

const handleFileUpload = (e) => {
  const file = e.target.files?.[0]
  if (!file) return
  
  fileName.value = file.name
  const reader = new FileReader()
  
  reader.onload = (evt) => {
    const wb = XLSX.read(new Uint8Array(evt.target.result), { type: 'array' })
    const ws = wb.Sheets[wb.SheetNames[0]]
    const raw = XLSX.utils.sheet_to_json(ws, { header: 1, defval: '' })
    
    if (raw.length < 2) return

    const headers = raw[0].map(h => (h === undefined || h === null) ? '' : String(h).trim())
    const rows = raw.slice(1)

    const catIdx = findHeaderIndex(headers, /категор|category|катег/) !== -1
      ? findHeaderIndex(headers, /категор|category|катег/)
      : 0

    const prodIdx = findHeaderIndex(headers, /назван|product|продукт|name/) !== -1
      ? findHeaderIndex(headers, /назван|product|продукт|name/)
      : 2

    const cats = new Map()
    let id = 0
    let curCat = null

    rows.forEach(row => {
      const r = Array.from({ length: headers.length }, (_, i) => row[i] ?? '')
      const catName = String(r[catIdx] ?? '').trim()
      
      if (catName) {
        curCat = catName
        if (!cats.has(curCat)) {
          cats.set(curCat, { id: `cat-${++id}`, name: curCat, children: [] })
        }
      }

      if (!curCat) return
      const cat = cats.get(curCat)
      const prodName = String(r[prodIdx] ?? '').trim()
      if (!prodName) return

      const prod = { id: `prod-${++id}`, name: prodName, children: [] }

      for (let i = 0; i < headers.length; i++) {
        if (i === catIdx || i === prodIdx) continue
        const hdr = headers[i] || `Колонка ${i}`
        const val = r[i]
        if (val === undefined || val === null) continue
        
        const s = String(val).replace(/\r?\n/g, ' ').trim()
        if (!s) continue
        prod.children.push({ id: `attr-${++id}`, name: `${hdr}: ${s}` })
      }

      if (prod.children.length === 0) {
        prod.children.push({ id: `attr-${++id}`, name: `—` })
      }

      cat.children.push(prod)
    })

    worlds.value = Array.from(cats.values())
  }

  reader.readAsArrayBuffer(file)
}
</script>

<template>
  <div class="app">
    <div class="controls">
      <label class="btn">
        Загрузить Excel
        <input type="file" @change="handleFileUpload" accept=".xlsx,.xls">
      </label>
      <span v-if="fileName" class="file-name">{{ fileName }}</span>
      
      <div v-if="worlds" class="search-box">
        <input 
          v-model="searchQuery"
          type="text" 
          placeholder="Поиск по категориям..."
          class="search-input"
        />
        <button 
          v-if="searchQuery"
          @click="clearSearch"
          class="clear-btn"
        >✕</button>
      </div>
      
      <span class="hint">Кликайте на узлы чтобы скрыть/показать</span>
    </div>

    <ForceDirectedTree :worlds="filteredWorlds" />
  </div>
</template>

<style>
@import 'components/styles/App.css';
</style>