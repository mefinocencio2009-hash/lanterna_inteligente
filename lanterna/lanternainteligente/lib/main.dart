import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:torch_light/torch_light.dart';

// ============================================================
//  ENTRY POINT
// ============================================================
void main() {
  runApp(const MainApp());
}

// ============================================================
//  APP / TEMA
// ============================================================
class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lanterna Inteligente',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppCores.amarelo,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: AppCores.fundo,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppCores.cinzaEscuro,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: const LanternaScreen(),
    );
  }
}

// ============================================================
//  PALETA DE CORES
// ============================================================
class AppCores {
  static const Color amarelo = Color(0xFFFFD700);
  static const Color fundo = Color(0xFF0D0D0D);
  static const Color cinzaEscuro = Color(0xFF1A1A1A);
  static const Color cinzaMedio = Color(0xFF2C2C2C);
  static const Color cinzaTexto = Color(0xFF888888);
  static const Color vermelho = Color(0xFFEF5350);
  static const Color azul = Color(0xFF42A5F5);
  static const Color verde = Color(0xFF66BB6A);
  static const Color roxo = Color(0xFFAB47BC);
}

// ============================================================
//  TELA PRINCIPAL
// ============================================================
class LanternaScreen extends StatefulWidget {
  const LanternaScreen({super.key});

  @override
  State<LanternaScreen> createState() => _LanternaScreenState();
}

class _LanternaScreenState extends State<LanternaScreen>
    with SingleTickerProviderStateMixin {
  // ---------------- ESTADO ----------------
  bool _ligada = false;
  bool _modoAutomatico = false;
  bool _sosAtivo = false;
  bool _processando = false;

  // Animação contínua do halo de luz
  late final AnimationController _pulsoController;
  late final Animation<double> _pulso;

  // Token para cancelar ciclos SOS antigos
  int _sosToken = 0;

  // ---------------- CICLO DE VIDA ----------------
  @override
  void initState() {
    super.initState();
    _pulsoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pulso = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulsoController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _sosAtivo = false;
    _sosToken++;
    _pulsoController.dispose();
    _torchSilencioso(false);
    super.dispose();
  }

  // ============================================================
  //  HARDWARE (com tratamento de permissão/erro)
  // ============================================================
  Future<bool> _aplicarTorch(bool ligar, {bool silencioso = false}) async {
    try {
      if (ligar) {
        final disponivel = await TorchLight.isTorchAvailable();
        if (!disponivel) {
          if (!silencioso) {
            _mostrarAviso('Este dispositivo não possui lanterna disponível.');
          }
          return false;
        }
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      return true;
    } on EnableTorchException {
      if (!silencioso) {
        _mostrarAviso(
          'Permissão de câmera negada. Autorize o acesso para usar a lanterna.',
        );
      }
      return false;
    } on DisableTorchException {
      return false;
    } catch (_) {
      if (!silencioso) {
        _mostrarAviso('Não foi possível controlar a lanterna do dispositivo.');
      }
      return false;
    }
  }

  Future<void> _torchSilencioso(bool ligar) async {
    try {
      if (ligar) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
    } catch (_) {
      // ignora erros silenciosos (SOS pisca muito rápido)
    }
  }

  void _mostrarAviso(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensagem),
        backgroundColor: AppCores.vermelho,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  //  AÇÕES DE ESTADO
  // ============================================================
  void _atualizarPulso(bool ligar) {
    if (ligar) {
      _pulsoController.repeat(reverse: true);
    } else {
      _pulsoController.stop();
      _pulsoController.reset();
    }
  }

  Future<void> _alternarLanterna() async {
    if (_processando || _sosAtivo) return;

    if (_modoAutomatico) {
      _mostrarAviso('Desative o Modo Automático para controlar manualmente.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _processando = true);

    final ligar = !_ligada;
    setState(() => _ligada = ligar);
    _atualizarPulso(ligar);

    await _aplicarTorch(ligar);

    if (mounted) setState(() => _processando = false);
  }

  Future<void> _alternarModoAutomatico(bool valor) async {
    HapticFeedback.selectionClick();
    setState(() => _modoAutomatico = valor);

    // Ao ativar o modo automático, liga a lanterna se estiver apagada
    if (valor && !_ligada) {
      setState(() => _ligada = true);
      _atualizarPulso(true);
      await _aplicarTorch(true);
    }
  }

  // ============================================================
  //  DESAFIO — MODO SOS
  // ============================================================
  Future<void> _alternarSOS() async {
    if (_sosAtivo) {
      setState(() => _sosAtivo = false);
      _sosToken++;
      return;
    }

    if (_modoAutomatico) {
      _mostrarAviso('Desative o Modo Automático para usar o SOS.');
      return;
    }

    HapticFeedback.heavyImpact();
    _sosToken++;
    final meuToken = _sosToken;
    setState(() => _sosAtivo = true);
    unawaited(_executarCicloSOS(meuToken));
  }

  Future<void> _executarCicloSOS(int token) async {
    const curto = Duration(milliseconds: 180);
    const longo = Duration(milliseconds: 540);
    const intervalo = Duration(milliseconds: 180);
    const entreLetras = Duration(milliseconds: 360);
    const entreCiclos = Duration(milliseconds: 1200);

    while (_sosAtivo && mounted && token == _sosToken) {
      // "S"  (...)
      for (var i = 0; i < 3 && _sosAtivo && token == _sosToken; i++) {
        await _piscar(curto, intervalo);
      }
      if (!_sosAtivo || token != _sosToken) break;
      await Future.delayed(entreLetras);

      // "O"  (---)
      for (var i = 0; i < 3 && _sosAtivo && token == _sosToken; i++) {
        await _piscar(longo, intervalo);
      }
      if (!_sosAtivo || token != _sosToken) break;
      await Future.delayed(entreLetras);

      // "S"  (...)
      for (var i = 0; i < 3 && _sosAtivo && token == _sosToken; i++) {
        await _piscar(curto, intervalo);
      }
      if (!_sosAtivo || token != _sosToken) break;
      await Future.delayed(entreCiclos);
    }

    // Limpeza final
    if (mounted && token == _sosToken) {
      setState(() {
        _sosAtivo = false;
        _ligada = false;
      });
      _pulsoController.stop();
      _pulsoController.reset();
      await _torchSilencioso(false);
    }
  }

  Future<void> _piscar(Duration ligado, Duration desligado) async {
    if (!_sosAtivo || !mounted) return;

    setState(() => _ligada = true);
    await _torchSilencioso(true);
    await Future.delayed(ligado);

    if (!_sosAtivo || !mounted) return;

    setState(() => _ligada = false);
    await _torchSilencioso(false);
    await Future.delayed(desligado);
  }

  // ============================================================
  //  BUILD
  // ============================================================
  Duration get _duracaoBulbo => _sosAtivo
      ? const Duration(milliseconds: 70)
      : const Duration(milliseconds: 400);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppCores.fundo,
      body: SafeArea(
        child: Column(
          children: [
            _construirCabecalho(),
            const SizedBox(height: 8),
            _construirCardModoAutomatico(),
            Expanded(child: Center(child: _construirBulbo())),
            _construirBotaoPower(),
            const SizedBox(height: 24),
            _construirBotaoSOS(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ---------- CABEÇALHO (identificação + badge de estado) ----------
  Widget _construirCabecalho() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '🔦 Lanterna',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _ligada ? AppCores.amarelo : AppCores.cinzaMedio,
              borderRadius: BorderRadius.circular(20),
              boxShadow: _ligada
                  ? [
                      BoxShadow(
                        color: AppCores.amarelo.withOpacity(0.55),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : const [],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 300),
              style: TextStyle(
                color: _ligada ? AppCores.fundo : AppCores.cinzaTexto,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
              child: Text(_ligada ? 'LIGADA' : 'DESLIGADA'),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- CARD MODO AUTOMÁTICO ----------
  Widget _construirCardModoAutomatico() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _modoAutomatico
              ? AppCores.roxo.withOpacity(0.22)
              : AppCores.cinzaEscuro,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _modoAutomatico ? AppCores.roxo : AppCores.cinzaMedio,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _modoAutomatico ? AppCores.roxo : AppCores.cinzaMedio,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_mode,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modo Automático',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _modoAutomatico
                          ? 'Ativo — lanterna ligada automaticamente'
                          : 'Liga sozinha quando o ambiente estiver escuro',
                      key: ValueKey(_modoAutomatico),
                      style: TextStyle(
                        color: _modoAutomatico
                            ? AppCores.roxo
                            : AppCores.cinzaTexto,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _modoAutomatico,
              onChanged: _alternarModoAutomatico,
              activeColor: AppCores.roxo,
            ),
          ],
        ),
      ),
    );
  }

  // ---------- REPRESENTAÇÃO VISUAL DA LANTERNA ----------
  Widget _construirBulbo() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Halo externo pulsante (só quando ligada)
        if (_ligada)
          ScaleTransition(
            scale: _pulso,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppCores.amarelo.withOpacity(0.35),
                    AppCores.amarelo.withOpacity(0.0),
                  ],
                  stops: const [0.35, 1.0],
                ),
              ),
            ),
          ),

        // Corpo da lanterna (bulbo)
        AnimatedContainer(
          duration: _duracaoBulbo,
          curve: Curves.easeInOut,
          width: _ligada ? 160 : 120,
          height: _ligada ? 160 : 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _ligada ? AppCores.amarelo : AppCores.cinzaMedio,
            boxShadow: _ligada
                ? [
                    BoxShadow(
                      color: AppCores.amarelo.withOpacity(0.75),
                      blurRadius: 60,
                      spreadRadius: 12,
                    ),
                    BoxShadow(
                      color: AppCores.amarelo.withOpacity(0.35),
                      blurRadius: 120,
                      spreadRadius: 30,
                    ),
                  ]
                : const [],
          ),
          child: AnimatedSwitcher(
            duration: _duracaoBulbo,
            child: Icon(
              _ligada ? Icons.flashlight_on : Icons.flashlight_off,
              key: ValueKey<bool>(_ligada),
              size: _ligada ? 72 : 56,
              color: _ligada ? AppCores.fundo : AppCores.cinzaTexto,
            ),
          ),
        ),
      ],
    );
  }

  // ---------- BOTÃO POWER ----------
  Widget _construirBotaoPower() {
    return GestureDetector(
      onTap: _alternarLanterna,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _ligada ? AppCores.amarelo : AppCores.cinzaMedio,
          border: Border.all(
            color: _ligada ? AppCores.amarelo : AppCores.cinzaEscuro,
            width: 2,
          ),
          boxShadow: _ligada
              ? [
                  BoxShadow(
                    color: AppCores.amarelo.withOpacity(0.65),
                    blurRadius: 30,
                    spreadRadius: 4,
                  ),
                ]
              : const [],
        ),
        child: Icon(
          Icons.power_settings_new,
          size: 40,
          color: _ligada ? AppCores.fundo : AppCores.cinzaTexto,
        ),
      ),
    );
  }

  // ---------- BOTÃO SOS (DESAFIO) ----------
  Widget _construirBotaoSOS() {
    return OutlinedButton.icon(
      onPressed: _alternarSOS,
      icon: Icon(_sosAtivo ? Icons.stop_circle : Icons.sos),
      label: Text(_sosAtivo ? 'Parar SOS' : 'Modo SOS'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _sosAtivo ? AppCores.vermelho : AppCores.cinzaTexto,
        side: BorderSide(
          color: _sosAtivo ? AppCores.vermelho : AppCores.cinzaMedio,
          width: 1.5,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }
}