// Aurora Capabilities Chart

        const auroraCtx = document.getElementById('auroraChart').getContext('2d');

        const auroraChart = new Chart(auroraCtx, {
            type: 'radar',
            data: {

                labels: ['Isbrytning', 'Forsvar', 'Hastighet', 'Autonomi', 'Miljøvennlighet'],
                datasets: [{
                    label: 'Aurora-klasse',
                    data: [95, 90, 85, 92, 88],
                    backgroundColor: 'rgba(93, 147, 255, 0.2)',
                    borderColor: '#5d93ff',
                    borderWidth: 2
                }, {
                    label: 'Konkurrenter',
                    data: [70, 75, 80, 60, 65],
                    backgroundColor: 'rgba(200, 200, 200, 0.2)',
                    borderColor: '#888888',
                    borderWidth: 2
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Aurora vs Konkurrenter - Kapabiliteter' }
                },
                scales: {
                    r: { beginAtZero: true, max: 100 }
                }
            }
        });
        // Fighter Jet Development Timeline
        const jetCtx = document.getElementById('jetChart').getContext('2d');
        const jetChart = new Chart(jetCtx, {
            type: 'line',
            data: {
                labels: ['2025', '2027', '2030', '2035', '2040'],

                datasets: [{
                    label: '7. Gen Kampfly',
                    data: [10, 50, 90, 100, 100],
                    borderColor: '#ff007f',
                    backgroundColor: 'rgba(255, 0, 127, 0.1)',
                    fill: true
                }, {
                    label: '8. Gen Kampfly',
                    data: [0, 10, 40, 80, 100],
                    borderColor: '#00c9ff',
                    backgroundColor: 'rgba(0, 201, 255, 0.1)',
                    fill: true
                }, {
                    label: '9-10. Gen Kampfly',
                    data: [0, 0, 5, 25, 60],
                    borderColor: '#ffcc00',
                    backgroundColor: 'rgba(255, 204, 0, 0.1)',
                    fill: true
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Kampfly Utvikling Timeline' }
                },
                scales: { y: { beginAtZero: true, max: 100 } }
            }
        });
        // Market Position Chart
        const marketCtx = document.getElementById('marketChart').getContext('2d');
        const marketChart = new Chart(marketCtx, {
            type: 'doughnut',
            data: {
                labels: ['SPEIS', 'Kongsberg', 'Andre'],

                datasets: [{
                    data: [35, 40, 25],
                    backgroundColor: ['#5d93ff', '#ff8c00', '#cccccc'],
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Forventet Markedsandel - Nordisk Aerospace' },
                    legend: { position: 'bottom' }
                }
            }
        });
        // Financial Projections Chart
        const financeCtx = document.getElementById('financeChart').getContext('2d');
        const financeChart = new Chart(financeCtx, {
            type: 'bar',
            data: {
                labels: ['År 1', 'År 2', 'År 3', 'År 4', 'År 5'],

                datasets: [{
                    label: 'Omsetning (MNOK)',
                    data: [50, 150, 400, 800, 1200],
                    backgroundColor: '#5d93ff',
                }, {
                    label: 'Netto Resultat (MNOK)',
                    data: [-100, -50, 50, 200, 400],
                    backgroundColor: '#ff007f',
                }]
            },
            options: {
                plugins: {
                    title: { display: true, text: 'Økonomiske Prognoser' }
                },
                scales: { y: { beginAtZero: false } }
            }
        });
