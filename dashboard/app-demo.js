// RAG Demo Dashboard Application - Static Demo Version
// This is a LIMITED DEMO with mocked data for GitHub Pages
// To use the full interactive version, clone and build locally

const MOCK_COLLECTIONS = [
    { name: 'documents' },
    { name: 'python-books' },
    { name: 'javascript-books' },
    { name: 'rust-books' }
];

const MOCK_SEARCH_RESULTS = [
    {
        score: 0.89,
        payload: {
            source: 'rust-programming-guide.pdf',
            text: 'Rust uses ownership as its core memory management paradigm. Every value has a single owner, and when the owner goes out of scope, the value is dropped. This prevents memory leaks and data races at compile time.'
        }
    },
    {
        score: 0.85,
        payload: {
            source: 'advanced-rust-concepts.pdf',
            text: 'Borrowing allows you to reference data without taking ownership. There are two types of borrows: immutable (&T) and mutable (&mut T). The borrow checker ensures that references are always valid.'
        }
    },
    {
        score: 0.82,
        payload: {
            source: 'rust-by-example.pdf',
            text: 'Lifetimes are Rust\'s way of ensuring references are valid for as long as they need to be. They are denoted with an apostrophe: \'a, \'b, etc. Most of the time, the compiler can infer lifetimes automatically.'
        }
    },
    {
        score: 0.78,
        payload: {
            source: 'rust-programming-guide.pdf',
            text: 'The Drop trait is Rust\'s destructor. It runs automatically when a value goes out of scope. You can implement custom cleanup logic by implementing Drop for your types.'
        }
    },
    {
        score: 0.75,
        payload: {
            source: 'practical-rust.pdf',
            text: 'Smart pointers like Box, Rc, and Arc provide heap allocation and reference counting. Box provides single ownership, Rc provides shared ownership for single-threaded code, and Arc provides shared ownership for multi-threaded code.'
        }
    }
];

class RagDashboardDemo {
    constructor() {
        this.currentCollection = 'documents';
        this.collections = MOCK_COLLECTIONS;
        this.init();
    }

    async init() {
        this.showDemoWarning();
        this.setupEventListeners();
        this.loadCollections();
        this.updateMockStatus();
    }

    showDemoWarning() {
        const warning = document.createElement('div');
        warning.style.cssText = `
            background: #fef3c7;
            border: 2px solid #f59e0b;
            color: #92400e;
            padding: 1rem;
            margin: 1rem 0;
            border-radius: 8px;
            text-align: center;
            font-weight: 600;
        `;
        warning.innerHTML = `
            ⚠️ <strong>Limited Demo:</strong> This is a static preview with mocked data.
            For the full interactive experience with real document search,
            <a href="https://github.com/softwarewrighter/rag-demo" style="color: #2563eb; text-decoration: underline;">
                clone the repository
            </a> and run it locally.
        `;

        const container = document.querySelector('.container');
        const header = container.querySelector('header');
        container.insertBefore(warning, header.nextSibling);
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

        // Set placeholder with a suggested query
        queryInput.placeholder = 'Try: "How does Rust handle memory management?"';
    }

    loadCollections() {
        const select = document.getElementById('collection-select');
        select.innerHTML = '';

        for (const collection of this.collections) {
            const option = document.createElement('option');
            option.value = collection.name;
            option.textContent = collection.name;
            if (collection.name === 'documents') {
                option.selected = true;
            }
            select.appendChild(option);
        }
    }

    updateMockStatus() {
        // Update status indicators with mocked values
        this.updateStatus('qdrant', 'Demo Mode', true);
        this.updateStatus('ollama', 'Demo Mode', true);
        this.updateStat('collections', '4');
        this.updateStat('vectors', '9,193');
    }

    async performSearch() {
        const queryInput = document.getElementById('query-input');
        const query = queryInput.value.trim();

        if (!query) {
            alert('Please enter a search query to see demo results');
            return;
        }

        const searchBtn = document.getElementById('search-btn');
        searchBtn.disabled = true;
        searchBtn.textContent = 'Searching...';

        const resultsSection = document.getElementById('results-section');
        const resultsContainer = document.getElementById('results-container');
        resultsSection.style.display = 'block';
        resultsContainer.innerHTML = '<div class="loading">Loading demo results...</div>';

        // Simulate search delay
        await new Promise(resolve => setTimeout(resolve, 800));

        // Show demo notice
        const demoNotice = document.createElement('div');
        demoNotice.style.cssText = `
            background: #e0f2fe;
            border-left: 4px solid #0ea5e9;
            padding: 1rem;
            margin-bottom: 1rem;
            border-radius: 4px;
            font-size: 0.9rem;
        `;
        demoNotice.innerHTML = `
            <strong>📌 Demo Results:</strong> These are pre-generated sample results about Rust programming.
            In the full version, results would be dynamically generated from your ingested documents.
        `;

        resultsContainer.innerHTML = '';
        resultsContainer.appendChild(demoNotice);

        // Display mock results
        this.displayResults(MOCK_SEARCH_RESULTS, query);

        searchBtn.disabled = false;
        searchBtn.textContent = 'Search';
    }

    displayResults(results, query) {
        const resultsContainer = document.getElementById('results-container');

        results.forEach((result, index) => {
            const card = document.createElement('div');
            card.className = 'result-card';

            const source = result.payload.source;
            const content = result.payload.text;
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
}

// Initialize the demo dashboard when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new RagDashboardDemo();
});
