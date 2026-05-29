var ctx = document.getElementById('marketChart').getContext('2d');
                var marketChart = new Chart(ctx, {
                    type: 'bar',

                    data: {
                        labels: ['Bergen', 'Oslo', 'Stavanger', 'Trondheim'],
                        datasets: [{
                            label: 'Støtte for Selvstyrepartiet',
                            data: [60, 45, 70, 50],
                            backgroundColor: 'rgba(93, 147, 255, 0.6)',
                            borderColor: 'rgba(93, 147, 255, 1)',
                            borderWidth: 1
                        }]
                    },
                    options: {
                        scales: {
                            y: {
                                beginAtZero: true
                            }
                        }
                    }
                });
