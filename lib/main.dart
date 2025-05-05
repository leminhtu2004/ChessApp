import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async';

void main() => runApp(const ChessApp());

class ChessApp extends StatelessWidget {
  const ChessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Chess',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: Colors.blueGrey[50],
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      home: const MainMenu(),
    );
  }
}

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CỜ VUA THÔNG MINH'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAboutDialog(
              context: context,
              applicationName: 'Smart Chess',
              applicationVersion: '1.0',
              children: [const Text('Ứng dụng cờ vua đa chế độ\nPhát triển bởi HUST')],
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildModeButton(context, 'Cờ Chớp (3+2)', const Duration(minutes: 3), 2),
            _buildModeButton(context, 'Cờ Nhanh (10+5)', const Duration(minutes: 10), 5),
            _buildModeButton(context, 'Cổ Điển (30+10)', const Duration(minutes: 30), 10),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(BuildContext context, String label, Duration duration, int increment) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(200, 50),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChessBoard(
              gameDuration: duration,
              increment: increment,
            ),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class ChessBoard extends StatefulWidget {
  final Duration gameDuration;
  final int increment;

  const ChessBoard({
    super.key,
    required this.gameDuration,
    this.increment = 0,
  });

  @override
  State<ChessBoard> createState() => _ChessBoardState();
}

class _ChessBoardState extends State<ChessBoard> {
  late List<List<String>> board;
  int? selectedRow;
  int? selectedCol;
  bool isRedTurn = true;
  late List<List<bool>> validMoves;
  bool gameOver = false;
  String? gameResult;
  int halfMoveClock = 0;
  List<String> positionHistory = [];
  String? _promotedPiece;
  List<String> _moveHistory = [];
  List<String> capturedByRed = [];
  List<String> capturedByBlack = [];
  
  Timer? _timer;
  late int _redTime;
  late int _blackTime;
  late int _increment;
  bool _showRepetitionWarning = false;
  bool _showFiftyMoveWarning = false;
  bool _showApproachingFifty = false;
  bool _showApproachingThreefold = false;
  bool _isDrawDialogShown = false;

  final Map<String, bool> castlingRights = {
    'redKingMoved': false,
    'redRookKingsideMoved': false,
    'redRookQueensideMoved': false,
    'blackKingMoved': false,
    'blackRookKingsideMoved': false,
    'blackRookQueensideMoved': false,
  };
  
  List<int?> enPassantSquare = [null, null];

  @override
  void initState() {
    super.initState();
    _redTime = widget.gameDuration.inSeconds;
    _blackTime = widget.gameDuration.inSeconds;
    _increment = widget.increment;
    _initializeGame();
    _startClock();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initializeGame() {
    board = List.generate(8, (i) => List.filled(8, ''));
    validMoves = List.generate(8, (_) => List.filled(8, false));
    positionHistory.clear();
    _moveHistory.clear();
    capturedByRed.clear();
    capturedByBlack.clear();
    halfMoveClock = 0;
    gameResult = null;
    
    board[0] = ['♜', '♞', '♝', '♛', '♚', '♝', '♞', '♜'];
    board[1] = List.filled(8, '♟');
    board[6] = List.filled(8, '♙');
    board[7] = ['♖', '♘', '♗', '♕', '♔', '♗', '♘', '♖'];
  }

  void _startClock() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (isRedTurn) _redTime = max(0, _redTime - 1);
        else _blackTime = max(0, _blackTime - 1);
        
        if (_redTime == 0 || _blackTime == 0) {
          _endGame(timeout: true);
        }
      });
    });
  }

  void _endGame({bool timeout = false}) {
    _timer?.cancel();
    gameOver = true;
    if (timeout) {
      gameResult = isRedTurn ? 'Đen thắng (hết giờ)' : 'Đỏ thắng (hết giờ)';
    }
  }

  void _pauseGame() {
    _timer?.cancel();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạm dừng'),
        content: const Text('Chọn hành động:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startClock();
            },
            child: const Text('Tiếp tục'),
          ),
          TextButton(
            onPressed: () {
              Navigator.popUntil(ctx, (route) => route.isFirst);
            },
            child: const Text('Thoát về menu'),
          ),
        ],
      ),
    );
  }

  bool _isRedPiece(String piece) => piece.runes.any((rune) => '♔♕♖♗♘♙'.runes.contains(rune));

  List<int> _findKing(bool isRed) {
    final king = isRed ? '♔' : '♚';
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        if (board[row][col] == king) return [row, col];
      }
    }
    return [-1, -1];
  }

  bool _isInCheck(bool isRed) {
    final kingPos = _findKing(isRed);
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty && _isRedPiece(piece) != isRed) {
          if (_validateMove(row, col, kingPos[0], kingPos[1], checkSafety: false)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  bool _hasSufficientMaterial() {
    List<String> pieces = [];
    for (var row in board) {
      for (var piece in row) {
        if (piece.isNotEmpty && !['♔', '♚'].contains(piece)) {
          pieces.add(piece);
        }
      }
    }
    if (pieces.isEmpty) return true;
    if (pieces.length == 1 && ['♗', '♝', '♘', '♞'].contains(pieces[0])) return true;
    if (pieces.length == 2 && pieces.every((p) => ['♗', '♝'].contains(p))) return true;
    return false;
  }

  void _checkDrawConditions() {
    final currentPosition = {
      'board': board.map((row) => List<String>.from(row)).toList(),
      'castlingRights': Map<String, bool>.from(castlingRights),
      'enPassant': List<int?>.from(enPassantSquare),
      'isRedTurn': !isRedTurn,
    };
    final current = jsonEncode(currentPosition);
    int repetitions = positionHistory.where((p) => p == current).length;
    
    _showApproachingThreefold = repetitions == 2;
    _showApproachingFifty = halfMoveClock >= 40 && halfMoveClock < 50;
    _showRepetitionWarning = repetitions >= 3;
    _showFiftyMoveWarning = halfMoveClock >= 50;

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showApproachingThreefold = false;
          _showApproachingFifty = false;
          _showRepetitionWarning = false;
          _showFiftyMoveWarning = false;
        });
      }
    });

    if (_hasSufficientMaterial()) {
      gameResult = 'Hòa do thiếu lực lượng';
      gameOver = true;
    }
  }

  bool _validateMove(int fromRow, int fromCol, int toRow, int toCol, {bool checkSafety = true}) {
    if (toRow < 0 || toRow >= 8 || toCol < 0 || toCol >= 8) return false;
    
    final piece = board[fromRow][fromCol];
    final target = board[toRow][toCol];
    final isRed = _isRedPiece(piece);
    
    if (piece.isEmpty || (target.isNotEmpty && _isRedPiece(target) == isRed)) return false;

    bool isValid = switch (piece) {
      '♙' || '♟' => _validatePawn(fromRow, fromCol, toRow, toCol, isRed),
      '♖' || '♜' => _validateRook(fromRow, fromCol, toRow, toCol),
      '♘' || '♞' => _validateKnight(fromRow, fromCol, toRow, toCol),
      '♗' || '♝' => _validateBishop(fromRow, fromCol, toRow, toCol),
      '♕' || '♛' => _validateQueen(fromRow, fromCol, toRow, toCol),
      '♔' || '♚' => _validateKing(fromRow, fromCol, toRow, toCol),
      _ => false,
    };

    return isValid && (!checkSafety || _simulateMoveSafety(fromRow, fromCol, toRow, toCol, isRed));
  }

  void _performMove(int fromRow, int fromCol, int toRow, int toCol, {bool checkSafety = false}) async {
    final piece = board[fromRow][fromCol];
    final isRed = _isRedPiece(piece);
    final isPawn = piece == '♙' || piece == '♟';
    final targetPiece = board[toRow][toCol];

    if (targetPiece.isNotEmpty) {
      if (_isRedPiece(targetPiece)) {
        capturedByBlack.add(targetPiece);
      } else {
        capturedByRed.add(targetPiece);
      }
    }

    halfMoveClock = (isPawn || targetPiece.isNotEmpty) ? 0 : halfMoveClock + 1;
    
    final currentPosition = {
      'board': board.map((row) => List<String>.from(row)).toList(),
      'castlingRights': Map<String, bool>.from(castlingRights),
      'enPassant': List<int?>.from(enPassantSquare),
      'isRedTurn': !isRedTurn,
    };
    positionHistory.add(jsonEncode(currentPosition));
    
    if (piece == '♔' || piece == '♚') {
      if ((toCol - fromCol).abs() == 2) _performCastling(fromRow, fromCol, toCol);
    } 
    else if (isPawn) {
      if (_validateEnPassant(fromRow, fromCol, toRow, toCol, isRed)) {
        board[enPassantSquare[0]!][enPassantSquare[1]!] = '';
      }
      enPassantSquare = (toRow - fromRow).abs() == 2 
          ? [(fromRow + toRow) ~/ 2, toCol]
          : [null, null];
    } else {
      enPassantSquare = [null, null];
    }

    board[toRow][toCol] = piece;
    board[fromRow][fromCol] = '';
    
    if (isRedTurn) _blackTime += _increment;
    else _redTime += _increment;

    if (isPawn) {
      final isRedPawn = _isRedPiece(piece);
      final promotionRow = isRedPawn ? 0 : 7;
      
      if (toRow == promotionRow) {
        _promotedPiece = isRedPawn ? '♕' : '♛';
        
        if (!checkSafety) {
          await _showPromotionDialog(toRow, toCol);
        }
        
        board[toRow][toCol] = _promotedPiece!;
      }
    }

    _updateCastlingRights(fromRow, fromCol);
    _checkDrawConditions();
    
    final moveNotation = _getMoveNotation(fromRow, fromCol, toRow, toCol);
    if (isRedTurn) {
      _moveHistory.add(moveNotation);
    } else {
      if (_moveHistory.isNotEmpty) {
        _moveHistory[_moveHistory.length - 1] += '\n$moveNotation';
      } else {
        _moveHistory.add('... $moveNotation');
      }
    }
  }

  String _getMoveNotation(int fromRow, int fromCol, int toRow, int toCol) {
    final piece = board[fromRow][fromCol];
    final pieceName = _getPieceName(piece);
    final from = _getChessNotation(fromRow, fromCol);
    final to = _getChessNotation(toRow, toCol);
    return '$pieceName $from → $to';
  }

  String _getPieceName(String symbol) {
    final isRed = _isRedPiece(symbol);
    final color = isRed ? 'Đỏ' : 'Đen';
    switch (symbol) {
      case '♔': return 'Vua $color';
      case '♕': return 'Hậu $color';
      case '♖': return 'Xe $color';
      case '♗': return 'Tượng $color';
      case '♘': return 'Mã $color';
      case '♙': return 'Tốt $color';
      case '♚': return 'Vua $color';
      case '♛': return 'Hậu $color';
      case '♜': return 'Xe $color';
      case '♝': return 'Tượng $color';
      case '♞': return 'Mã $color';
      case '♟': return 'Tốt $color';
      default: return '';
    }
  }

  Future<void> _showPromotionDialog(int row, int col) async {
    final isRed = _isRedPiece(board[row][col]);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Chọn quân phong cấp'),
          content: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPromotionOption(isRed ? '♕' : '♛'),
              _buildPromotionOption(isRed ? '♖' : '♜'),
              _buildPromotionOption(isRed ? '♗' : '♝'),
              _buildPromotionOption(isRed ? '♘' : '♞'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPromotionOption(String piece) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _promotedPiece = piece;
          Navigator.of(context).pop();
        });
      },
      child: Text(piece, style: TextStyle(fontSize: 32, color: _isRedPiece(piece) ? Colors.red : Colors.black)),
    );
  }

  String _getChessNotation(int row, int col) {
    final letters = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
    return '${letters[col]}${8 - row}';
  }

  bool _validatePawn(int fromRow, int fromCol, int toRow, int toCol, bool isRed) {
    final direction = isRed ? -1 : 1;
    final startRow = isRed ? 6 : 1;
    final isForward = fromCol == toCol;
    final isCapture = (toCol - fromCol).abs() == 1;

    if (isForward) {
      if (board[toRow][toCol].isNotEmpty) return false;
      if (toRow == fromRow + direction) return true;
      if (fromRow == startRow && 
          toRow == fromRow + 2 * direction && 
          board[fromRow + direction][fromCol].isEmpty) return true;
    }

    if (isCapture && toRow == fromRow + direction) {
      return board[toRow][toCol].isNotEmpty || _validateEnPassant(fromRow, fromCol, toRow, toCol, isRed);
    }

    return false;
  }

  bool _validateEnPassant(int fromRow, int fromCol, int toRow, int toCol, bool isRed) {
    if (enPassantSquare[0] == null) return false;
    final epRow = enPassantSquare[0]!;
    final epCol = enPassantSquare[1]!;
    final direction = isRed ? -1 : 1;
    final expectedFromRow = epRow - direction;
    return toRow == epRow && 
           toCol == epCol && 
           fromRow == expectedFromRow && 
           (fromCol == epCol - 1 || fromCol == epCol + 1);
  }

  bool _validateRook(int fromRow, int fromCol, int toRow, int toCol) {
    if (fromRow != toRow && fromCol != toCol) return false;
    return _isPathClear(fromRow, fromCol, toRow, toCol);
  }

  bool _validateKnight(int fromRow, int fromCol, int toRow, int toCol) {
    final dx = (toCol - fromCol).abs();
    final dy = (toRow - fromRow).abs();
    return (dx == 1 && dy == 2) || (dx == 2 && dy == 1);
  }

  bool _validateBishop(int fromRow, int fromCol, int toRow, int toCol) {
    if ((toRow - fromRow).abs() != (toCol - fromCol).abs()) return false;
    return _isPathClear(fromRow, fromCol, toRow, toCol);
  }

  bool _validateQueen(int fromRow, int fromCol, int toRow, int toCol) {
    return _validateRook(fromRow, fromCol, toRow, toCol) || 
           _validateBishop(fromRow, fromCol, toRow, toCol);
  }

  bool _validateKing(int fromRow, int fromCol, int toRow, int toCol) {
    final dx = (toCol - fromCol).abs();
    final dy = (toRow - fromRow).abs();
    if (dx <= 1 && dy <= 1) return true;
    return _validateCastling(fromRow, fromCol, toRow, toCol);
  }

  bool _validateCastling(int kingRow, int kingCol, int toRow, int toCol) {
    if (kingRow != toRow || (toCol - kingCol).abs() != 2) return false;
    final isRed = _isRedPiece(board[kingRow][kingCol]);
    if (_isInCheck(isRed)) return false;
    
    final side = isRed ? 'red' : 'black';
    final rookCol = toCol > kingCol ? 7 : 0;
    final rookPiece = isRed ? '♖' : '♜';
    
    final step = (toCol > kingCol) ? 1 : -1;
    for (int i = 1; i <= 2; i++) {
      if (_isSquareUnderAttack(kingRow, kingCol + step * i, !isRed)) {
        return false;
      }
    }
    
    return !castlingRights['${side}KingMoved']! &&
           !castlingRights['${side}Rook${rookCol == 7 ? 'Kingside' : 'Queenside'}Moved']! &&
           board[kingRow][rookCol] == rookPiece &&
           _isPathClear(kingRow, kingCol, kingRow, rookCol);
  }

  bool _isSquareUnderAttack(int row, int col, bool attackerIsRed) {
    for (int r = 0; r < 8; r++) {
      for (int c = 0; c < 8; c++) {
        final piece = board[r][c];
        if (piece.isNotEmpty && _isRedPiece(piece) == attackerIsRed) {
          if (_validateMove(r, c, row, col, checkSafety: false)) return true;
        }
      }
    }
    return false;
  }

  void _performCastling(int kingRow, int kingCol, int toCol) {
    final isRed = _isRedPiece(board[kingRow][kingCol]);
    final rookCol = toCol > kingCol ? 7 : 0;
    final newRookCol = toCol > kingCol ? kingCol + 1 : kingCol - 1;
    
    board[kingRow][newRookCol] = board[kingRow][rookCol];
    board[kingRow][rookCol] = '';
    
    final side = isRed ? 'red' : 'black';
    castlingRights['${side}KingMoved'] = true;
  }

  void _updateCastlingRights(int row, int col) {
    final piece = board[row][col];
    final isRed = _isRedPiece(piece);
    final side = isRed ? 'red' : 'black';
    
    switch (piece) {
      case '♔':
      case '♚':
        castlingRights['${side}KingMoved'] = true;
        break;
      case '♖':
      case '♜':
        if (col == 0) castlingRights['${side}RookQueensideMoved'] = true;
        if (col == 7) castlingRights['${side}RookKingsideMoved'] = true;
        break;
    }
  }

  bool _isPathClear(int fromRow, int fromCol, int toRow, int toCol) {
    final dx = (toCol - fromCol).sign;
    final dy = (toRow - fromRow).sign;
    final steps = max((toRow - fromRow).abs(), (toCol - fromCol).abs());
    
    for (int i = 1; i < steps; i++) {
      final r = fromRow + dy * i;
      final c = fromCol + dx * i;
      if (board[r][c].isNotEmpty) return false;
    }
    return true;
  }

  bool _isCheckmate(bool isRed) {
    if (!_isInCheck(isRed)) return false;
    
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty && _isRedPiece(piece) == isRed) {
          for (int toRow = 0; toRow < 8; toRow++) {
            for (int toCol = 0; toCol < 8; toCol++) {
              if (_validateMove(row, col, toRow, toCol)) return false;
            }
          }
        }
      }
    }
    return true;
  }

  bool _isStalemate(bool isRed) {
    if (_isInCheck(isRed)) return false;
    
    for (int row = 0; row < 8; row++) {
      for (int col = 0; col < 8; col++) {
        final piece = board[row][col];
        if (piece.isNotEmpty && _isRedPiece(piece) == isRed) {
          for (int toRow = 0; toRow < 8; toRow++) {
            for (int toCol = 0; toCol < 8; toCol++) {
              if (_validateMove(row, col, toRow, toCol)) return false;
            }
          }
        }
      }
    }
    return true;
  }

  bool _isThreefoldRepetition() => positionHistory
      .where((p) => p == jsonEncode({
            'board': board,
            'castlingRights': castlingRights,
            'enPassant': enPassantSquare,
            'isRedTurn': isRedTurn,
          }))
      .length >= 3;

  bool _isFiftyMoveRule() => halfMoveClock >= 100;

  bool _simulateMoveSafety(int fromRow, int fromCol, int toRow, int toCol, bool isRed) {
    final originalBoard = board.map((row) => List<String>.from(row)).toList();
    final originalCastling = Map<String, bool>.from(castlingRights);
    final originalEnPassant = List<int?>.from(enPassantSquare);
    
    _performMove(fromRow, fromCol, toRow, toCol, checkSafety: true);
    final inCheck = _isInCheck(isRed);
    
    board = originalBoard;
    castlingRights.clear();
    castlingRights.addAll(originalCastling);
    enPassantSquare = originalEnPassant;
    
    return !inCheck;
  }

  @override
  Widget build(BuildContext context) {
    final redKingPos = _findKing(true);
    final blackKingPos = _findKing(false);
    final redInCheck = _isInCheck(true);
    final blackInCheck = _isInCheck(false);

    return Scaffold(
      appBar: AppBar(
     title: Column(
  children: [
    Text(
      gameResult ??
          (gameOver
              ? 'Kết thúc trận đấu'
              : isRedTurn
                  ? 'Lượt Đỏ${redInCheck ? ' (CHIẾU)' : ''}'
                  : 'Lượt Đen${blackInCheck ? ' (CHIẾU)' : ''}'),
      style: Theme.of(context).textTheme.titleLarge,
    ),
    Text(
      '${_formatTime(_redTime)} - ${_formatTime(_blackTime)}',
      style: const TextStyle(fontSize: 16),
    ),
  ],
),

        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.pause),
            onPressed: _pauseGame,
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                if (_showApproachingFifty || _showApproachingThreefold || _showRepetitionWarning || _showFiftyMoveWarning)
                  Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.amber[100],
                    child: Column(
                      children: [
                        if (_showApproachingFifty)
                          Text(
                            'Cảnh báo: Đã qua ${halfMoveClock} nước không ăn quân! (Cần ${50 - halfMoveClock} nước nữa để hòa)',
                            style: TextStyle(color: Colors.orange[800]),
                          ),
                        if (_showApproachingThreefold)
                          Text(
                            'Cảnh báo: Đã lặp nước 2 lần! Thêm 1 lần nữa sẽ hòa!',
                            style: TextStyle(color: Colors.orange[800]),
                          ),
                        if (_showRepetitionWarning)
                          Text(
                            'Hòa do lặp nước 3 lần!',
                            style: TextStyle(color: Colors.red[800]),
                          ),
                        if (_showFiftyMoveWarning)
                          Text(
                            'Hòa theo luật 50 nước!',
                            style: TextStyle(color: Colors.red[800]),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30, vertical: 30),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.blueGrey, width: 2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: GridView.builder(
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                              ),
                              itemCount: 64,
                              itemBuilder: (context, index) {
                                final row = index ~/ 8;
                                final col = index % 8;
                                final isKingInCheck = (redInCheck && row == redKingPos[0] && col == redKingPos[1]) ||
                                                  (blackInCheck && row == blackKingPos[0] && col == blackKingPos[1]);
                                
                                return _buildChessSquare(row, col, isKingInCheck);
                              },
                            ),
                          ),
                          Positioned(
                            left: -24,
                            top: 0,
                            bottom: 0,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(8, (index) => Text(
                                '${8 - index}',
                                style: TextStyle(
                                  color: Colors.blueGrey[800],
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold
                                ),
                              )).reversed.toList(),
                            ),
                          ),
                          Positioned(
                            right: -24,
                            top: 0,
                            bottom: 0,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(8, (index) => Text(
                                '${8 - index}',
                                style: TextStyle(
                                  color: Colors.blueGrey[800],
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold
                                ),
                              )).reversed.toList(),
                            ),
                          ),
                          Positioned(
                            top: -24,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(8, (index) => Text(
                                String.fromCharCode(97 + index),
                                style: TextStyle(
                                  color: Colors.blueGrey[800],
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold
                                ),
                              )),
                            ),
                          ),
                          Positioned(
                            bottom: -24,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: List.generate(8, (index) => Text(
                                String.fromCharCode(97 + index),
                                style: TextStyle(
                                  color: Colors.blueGrey[800],
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold
                                ),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Container(
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Colors.grey)),
              ),
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: _moveHistory.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: index % 2 == 0 ? Colors.blueGrey[50] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nước ${index + 1}:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey[800],
                                  ),
                                ),
                                ..._moveHistory[index].split('\n').map((move) => Padding(
                                  padding: const EdgeInsets.only(left: 16, top: 4),
                                  child: Text(
                                    '• $move',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: move.startsWith('Tốt Đỏ') ? Colors.red[700] : Colors.blueGrey[800],
                                    ),
                                  ),
                                )).toList(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(height: 2, color: Colors.grey),
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        _buildCapturedPieces('Đỏ đã ăn', capturedByRed, Colors.red),
                        _buildCapturedPieces('Đen đã ăn', capturedByBlack, Colors.black),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: gameOver
          ? FloatingActionButton(
              onPressed: () => setState(() {
                _initializeGame();
                _redTime = widget.gameDuration.inSeconds;
                _blackTime = widget.gameDuration.inSeconds;
                gameOver = false;
                isRedTurn = true;
                _startClock();
              }),
              child: const Icon(Icons.replay),
            )
          : _isDrawDialogShown 
              ? null 
              : FloatingActionButton(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Đề nghị hòa'),
                      content: const Text('Đối phương phải đồng ý để hòa'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              gameResult = 'Hòa do thỏa thuận';
                              gameOver = true;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('Gửi đề nghị'),
                        ),
                      ],
                    ),
                  ),
                  child: const Icon(Icons.handshake),
                ),
    );
  }

  Widget _buildCapturedPieces(String title, List<String> pieces, Color titleColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: titleColor,
                fontSize: 14,
              ),
            ),
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: pieces.map((piece) => Text(
                  piece,
                  style: TextStyle(
                    fontSize: 20,
                    color: _isRedPiece(piece) ? Colors.red : Colors.black,
                  ),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChessSquare(int row, int col, bool isKingInCheck) {
    final isSelected = row == selectedRow && col == selectedCol;
    final isValid = validMoves[row][col];
    final isDark = (row + col).isOdd;

    return GestureDetector(
      onTap: () => _handleTileTap(row, col),
      child: Container(
        decoration: BoxDecoration(
          color: isKingInCheck 
              ? Colors.red[300] 
              : isSelected 
                  ? Colors.amber.withOpacity(0.3)
                  : isDark 
                      ? Colors.blueGrey[300] 
                      : Colors.white,
          border: Border.all(
            color: isKingInCheck ? Colors.red : Colors.blueGrey[100]!,
            width: isKingInCheck ? 3 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                board[row][col],
                style: TextStyle(
                  fontSize: 32,
                  color: _isRedPiece(board[row][col]) 
                      ? Colors.red[700] 
                      : Colors.black,
                ),
              ),
            ),
            if (isValid)
              Positioned.fill(
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: board[row][col].isEmpty
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    border: Border.all(
                      color: board[row][col].isEmpty
                          ? Colors.green
                          : Colors.red,
                      width: 2,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remaining = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remaining';
  }

  void _handleTileTap(int row, int col) {
    if (gameOver) return;

    setState(() {
      if (selectedRow == null) {
        if (board[row][col].isNotEmpty && _isRedPiece(board[row][col]) == isRedTurn) {
          selectedRow = row;
          selectedCol = col;
          validMoves = List.generate(8, (i) => 
            List.generate(8, (j) => _validateMove(row, col, i, j)));
        }
      } else {
        if (validMoves[row][col]) {
          _performMove(selectedRow!, selectedCol!, row, col);
          
          if (_isCheckmate(!isRedTurn)) {
            gameResult = 'Chiếu hết! ${isRedTurn ? 'Đỏ thắng' : 'Đen thắng'}';
            gameOver = true;
          } else if (_isStalemate(isRedTurn)) {
            gameResult = 'Hòa do hết nước đi!';
            gameOver = true;
          } else if (_isThreefoldRepetition()) {
            gameResult = 'Hòa do lặp nước 3 lần!';
            gameOver = true;
          } else if (_isFiftyMoveRule()) {
            gameResult = 'Hòa theo luật 50 nước!';
            gameOver = true;
          }
          
          isRedTurn = !isRedTurn;
          _startClock();
        }
        selectedRow = null;
        validMoves = List.generate(8, (_) => List.filled(8, false));
      }
    });
  }
}