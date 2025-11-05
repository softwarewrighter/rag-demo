// RAG Demo Dashboard Application
const API_QDRANT = 'http://localhost:6333';
const API_OLLAMA = 'http://localhost:11434';
const DEFAULT_COLLECTION = 'documents';
const EMBEDDING_MODEL = 'nomic-embed-text';
const LLM_MODEL = 'llama3.2';

class RagDashboard {
    constructor() {
        this.currentCollection = DEFAULT_COLLECTION;
        this.collections = [];
        this.init();
    }

    async init() {
        this.setupEventListeners();
        await this.checkSystemStatus();
        await this.loadCollections();
        this.startStatusPolling();
    }

    setupEventListeners() {
        const searchBtn = document.getElementById('search-btn');
        const queryInput = document.getElementById('query-input');
        const collectionSelect = document.getElementById('collection-select');

        searchBtn.addEventListener('click', () => this.performSearch());
        queryInput.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') this.performSearch();
        });
        collectionSelect.addEventListener('change', (e) => {
            this.currentCollection = e.target.value;
        });
    }

    async checkSystemStatus() {
        // Check Qdrant
        try {
            const response = await fetch(`${API_QDRANT}/collections`);
            if (response.ok) {
                this.updateStatus('qdrant', 'Running', true);
                const data = await response.json();
                const collections = data.result?.collections || [];

                let totalVectors = 0;
                for (const collection of collections) {
                    const collectionData = await this.getCollectionInfo(collection.name);
                    totalVectors += collectionData.vectors_count || 0;
                }

                this.updateStat('collections', collections.length);
                this.updateStat('vectors', totalVectors.toLocaleString());
            } else {
                this.updateStatus('qdrant', 'Error', false);
            }
        } catch (error) {
            this.updateStatus('qdrant', 'Offline', false);
        }

        // Check Ollama
        try {
            const response = await fetch(`${API_OLLAMA}/api/tags`);
            if (response.ok) {
                this.updateStatus('ollama', 'Running', true);
            } else {
                this.updateStatus('ollama', 'Error', false);
            }
        } catch (error) {
            this.updateStatus('ollama', 'Offline', false);
        }
    }

    async loadCollections() {
        try {
            const response = await fetch(`${API_QDRANT}/collections`);
            if (!response.ok) throw new Error('Failed to fetch collections');

            const data = await response.json();
            this.collections = data.result?.collections || [];

            const select = document.getElementById('collection-select');
            select.innerHTML = '';

            if (this.collections.length === 0) {
                select.innerHTML = '<option value="">No collections available</option>';
                return;
            }

            for (const collection of this.collections) {
                const option = document.createElement('option');
                option.value = collection.name;
                option.textContent = collection.name;
                if (collection.name === DEFAULT_COLLECTION) {
                    option.selected = true;
                }
                select.appendChild(option);
            }
        } catch (error) {
            console.error('Error loading collections:', error);
            const select = document.getElementById('collection-select');
            select.innerHTML = '<option value="">Error loading collections</option>';
        }
    }

    async getCollectionInfo(collectionName) {
        try {
            const response = await fetch(`${API_QDRANT}/collections/${collectionName}`);
            if (!response.ok) return { vectors_count: 0 };
            const data = await response.json();
            return data.result || { vectors_count: 0 };
        } catch (error) {
            return { vectors_count: 0 };
        }
    }

    async performSearch() {
        const queryInput = document.getElementById('query-input');
        const query = queryInput.value.trim();

        if (!query) {
            alert('Please enter a search query');
            return;
        }

        const searchBtn = document.getElementById('search-btn');
        searchBtn.disabled = true;
        searchBtn.textContent = 'Searching...';

        const resultsSection = document.getElementById('results-section');
        const resultsContainer = document.getElementById('results-container');
        resultsSection.style.display = 'block';
        resultsContainer.innerHTML = '<div class="loading">Generating embeddings and searching...</div>';

        try {
            // Generate embeddings for the query
            const embedding = await this.generateEmbedding(query);

            // Search Qdrant
            const results = await this.searchVectors(embedding);

            // Display results
            this.displayResults(results, query);
        } catch (error) {
            console.error('Search error:', error);
            resultsContainer.innerHTML = `
                <div class="error-message">
                    Error performing search: ${error.message}
                </div>
            `;
        } finally {
            searchBtn.disabled = false;
            searchBtn.textContent = 'Search';
        }
    }

    async generateEmbedding(text) {
        const response = await fetch(`${API_OLLAMA}/api/embeddings`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                model: EMBEDDING_MODEL,
                prompt: text
            })
        });

        if (!response.ok) {
            throw new Error('Failed to generate embedding');
        }

        const data = await response.json();
        return data.embedding;
    }

    async searchVectors(embedding) {
        const response = await fetch(`${API_QDRANT}/collections/${this.currentCollection}/points/search`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                vector: embedding,
                limit: 5,
                with_payload: true
            })
        });

        if (!response.ok) {
            throw new Error('Failed to search vectors');
        }

        const data = await response.json();
        return data.result || [];
    }

    displayResults(results, query) {
        const resultsContainer = document.getElementById('results-container');

        if (results.length === 0) {
            resultsContainer.innerHTML = '<div class="loading">No results found.</div>';
            return;
        }

        resultsContainer.innerHTML = '';

        results.forEach((result, index) => {
            const card = document.createElement('div');
            card.className = 'result-card';

            const source = result.payload?.source || result.payload?.file || 'Unknown';
            const content = result.payload?.text || result.payload?.content || 'No content available';
            const score = (result.score * 100).toFixed(1);

            card.innerHTML = `
                <div class="result-header">
                    <div class="result-source">${this.escapeHtml(source)}</div>
                    <div class="result-score">Score: ${score}%</div>
                </div>
                <div class="result-content">${this.escapeHtml(content)}</div>
            `;

            resultsContainer.appendChild(card);
        });
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    updateStatus(service, status, isHealthy) {
        const statElement = document.getElementById(`stat-${service}`);
        statElement.textContent = status;
        statElement.className = `stat-value ${isHealthy ? 'success' : 'error'}`;
    }

    updateStat(statName, value) {
        const statElement = document.getElementById(`stat-${statName}`);
        if (statElement) {
            statElement.textContent = value;
        }
    }

    startStatusPolling() {
        // Poll status every 30 seconds
        setInterval(() => this.checkSystemStatus(), 30000);
    }
}

// Initialize the dashboard when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new RagDashboard();
});
