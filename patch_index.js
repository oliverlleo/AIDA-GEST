const fs = require('fs');
const file = 'index.html';
let content = fs.readFileSync(file, 'utf8');

const replacement = `
                                            <div>
                                                <div class="font-bold text-gray-800 text-sm" x-text="t.client_name"></div>
                                                <div class="text-xs text-gray-500" x-text="t.device_model + ' - OS: ' + t.os_number"></div>

                                                <!-- Dynamic sub-stage visual -->
                                                <div class="mt-1 text-xs font-semibold"
                                                     :class="{
                                                         'text-blue-600': t.status === 'Analise Tecnica' && !t.analysis_started_at,
                                                         'text-orange-600': t.status === 'Analise Tecnica' && t.analysis_started_at,
                                                         'text-green-600': t.status === 'Aprovacao' && t.budget_status !== 'Enviado'
                                                     }">
                                                    <span x-text="
                                                        (t.status === 'Analise Tecnica' && !t.analysis_started_at) ? 'Enviado para análise' :
                                                        (t.status === 'Analise Tecnica' && t.analysis_started_at) ? 'Análise em andamento' :
                                                        (t.status === 'Aprovacao' && t.budget_status !== 'Enviado') ? 'Análise finalizada' : t.status
                                                    "></span>
                                                </div>

                                                <!-- Deadlines -->
`;

content = content.replace(
    /<div>\s*<div class="font-bold text-gray-800 text-sm" x-text="t\.client_name"><\/div>\s*<div class="text-xs text-gray-500" x-text="t\.device_model \+ ' - OS: ' \+ t\.os_number"><\/div>\s*<!-- Deadlines -->/s,
    replacement.trim()
);

fs.writeFileSync(file, content);
